#!/bin/bash -e
set -x
scriptdir=$(realpath $(dirname "$0"))
source ${scriptdir}/common.sh
source ${scriptdir}/functions.sh

### basic functions

function retry() {
    local i
    for ((i=0; i<5; ++i)) ; do
        $@ && break
        sleep 5
    done
    [[ $i == 5 ]] && return 1
}

function is_registry_insecure() {
    echo "DEBUG: is_registry_insecure: $@"
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        echo "DEBUG: is_registry_insecure: $registry is insecure"
        return 0
    fi
    echo "DEBUG: is_registry_insecure: $registry is secure"
    return 1
}

function check_docker_value() {
    local name=$1
    local value=$2
    python -c "import json; f=open('/etc/docker/daemon.json'); data=json.load(f); print(data.get('$name'));" 2>/dev/null| grep -qi "$value"
}

function ensure_root() {
    local me=$(whoami)
    if [ "$me" != 'root' ] ; then
        echo "ERROR: this script requires root:"
        echo "       sudo -E $0"
        return 1
    fi
}

### install_docker_DISTRO functions

function install_docker_ubuntu() {
    export DEBIAN_FRONTEND=noninteractive
    which docker && return
    retry apt-get update
    retry apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository -y -u "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    retry apt-get install -y "docker-ce=18.06.3~ce~3-0~ubuntu"
}

function install_docker_centos() {
    which docker && return
    yum install -y yum-utils device-mapper-persistent-data lvm2
    if ! yum info docker-ce &> /dev/null ; then
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    retry yum install -y docker-ce-18.03.1.ce
}

function install_docker_rhel() {
    which docker && return
    if [ "$RHEL_VERSION" != "rhel8" ]; then
        sudo yum install -y docker device-mapper-libs device-mapper-event-libs
    else
        sudo yum install -y podman device-mapper-libs device-mapper-event-libs
        sudo ln -s "$(which podman)" /usr/bin/docker
    fi
}

### configure_insecure_registries_[/etc directory]

function configure_insecure_registries_containers() {
    ADDED_REGISTRY="$1"
    INSECURE_REGISTRIES="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$DOCKER_CONFIG" | tr -d '[]')"
    echo "INFO: old registries are $INSECURE_REGISTRIES"
    #INSECURE_REGISTRIES="registries =[$(echo "$INSECURE_REGISTRIES'$ADDED_REGISTRY' " | sed 's/ \+/,/g')]"
    INSECURE_REGISTRIES="registries =[$INSECURE_REGISTRIES, '$ADDED_REGISTRY']"
    echo "INFO: new registries are $INSECURE_REGISTRIES"
    sudo sed -i "/registries.insecure/{n; s/registries = .*$/${INSECURE_REGISTRIES}/g}" ${DOCKER_CONFIG}
}

function configure_insecure_registries_sysconfig() {
    ADDED_REGISTRY="$1"
    echo "INFO: add REGISTRY=$ADDED_REGISTRY to insecure list"
    INSECURE_REGISTRIES+=" --insecure-registry $ADDED_REGISTRY"
    sudo sed -i '/^INSECURE_REGISTRY/d' "$DOCKER_CONFIG"
    echo "INSECURE_REGISTRY=\"$INSECURE_REGISTRIES\""  | sudo tee -a "$DOCKER_CONFIG"
    sudo cat "$DOCKER_CONFIG"
}

function configure_insecure_registries_docker() {
    ADDED_REGISTRY="$1"
    python <<EOF
import json
data=dict()
try:
  with open("${DOCKER_CONFIG}") as f:
    data = json.load(f)
except Exception:
  pass

data.setdefault('insecure-registries', list()).append("${ADDED_REGISTRY}")

data['live-restore'] = True
with open("${DOCKER_CONFIG}", 'w') as f:
  data = json.dump(data, f, sort_keys=True, indent=4)
EOF
}

### end of function's declaration

ensure_root

echo -e "\n[docker install]"
echo "$DISTRO detected"

[ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "rhel" ] || ! echo "ERROR:  unknown distro $DISTRO" || exit 1

if ! which docker >/dev/null 2>&1 ; then
    [ "$DISTRO" == "ubuntu" ] || systemctl stop firewalld || true
    install_docker_$DISTRO
    [ "$DISTRO" == "ubuntu" ] || [ "$RHEL_VERSION" == "rhel8" ] || systemctl start docker
else
  echo "docker installed: $(docker --version)"
fi

echo -e "\n[docker config]"

# CONTAINER_REGISTRY's checks for definition and secureness
[ -n "${CONTAINER_REGISTRY}" ] || ! echo "${CONTAINER_REGISTRY} is not defined." || exit

if ! is_registry_insecure "$CONTAINER_REGISTRY" && [ -n "$TF_TEST_IMAGE_REGISTRY" ] && ! is_registry_insecure "$TF_TEST_IMAGE_REGISTRY" ; then
    echo "both $CONTAINER_REGISTRY and $TF_TEST_IMAGE_REGISTRY are secure"
    exit
fi

# finding out DOCKER_CONFIG file
INSECURE_REGISTRIES=""
if [ "$RHEL_VERSION" == "rhel8" ]; then
    DOCKER_CONFIG="/etc/containers/registries.conf"
    #echo "INFO:  rhel8 /etc/containers/registries.conf bug fix"
    #INSECURE_REGISTRIES="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$DOCKER_CONFIG" | tr -d '[]')"
    #INSECURE_REGISTRIES="registries =[$(echo $INSECURE_REGISTRIES | sed 's/ \+/,/g' |  sed 's/,\+/,/g')]"
    #sudo sed -i "/registries.insecure/{n; s/registries = .*$/${INSECURE_REGISTRIES}/g}" ${DOCKER_CONFIG}
else
    if [ -e "/etc/sysconfig/docker" ]; then
        INSECURE_REGISTRIES=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
        echo "INFO: current /etc/sysconfig/docker insecure_registries=$INSECURE_REGISTRIES"
    fi
    DOCKER_CONFIG=$([[ -z $INSECURE_REGISTRIES ]] && echo "/etc/docker/daemon.json" || echo "/etc/sysconfig/docker" )
fi

# if DOCKER_CONFIG already contains CONTAINER_REGISTRY --> exit
if [ -e $DOCKER_CONFIG ] && grep -q $CONTAINER_REGISTRY $DOCKER_CONFIG; then
    echo "Registry $CONTAINER_REGISTRY is configured in $DOCKER_CONFIG. Skip."
    exit 0
fi

[ -e $DOCKER_CONFIG ] || touch $DOCKER_CONFIG

# add CONTAINER_REGISTRY and TF_TEST_IMAGE into DOCKER_CONFIG
DOCKER_CONFIG_DIR=$(echo "$DOCKER_CONFIG" | cut -d "/" -f3 )
is_registry_insecure "$CONTAINER_REGISTRY" || configure_insecure_registries_$DOCKER_CONFIG_DIR "$CONTAINER_REGISTRY"
[ -z "$TF_TEST_IMAGE_REGISTRY" ] || is_registry_insecure "$TF_TEST_IMAGE_REGISTRY" || configure_insecure_registries_$DOCKER_CONFIG_DIR "$TF_TEST_IMAGE_REGISTRY"

echo -e "\n[restart docker]"

[ "$DISTRO" == "ubuntu" ] || [ "$RHEL_VERSION" == "rhel8" ] || systemctl restart docker
[ "$DISTRO" == "ubuntu" ] && service docker reload

