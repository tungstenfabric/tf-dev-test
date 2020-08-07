#!/bin/bash -e
set -x
scriptdir=$(realpath $(dirname "$0"))
source ${scriptdir}/common.sh
source ${scriptdir}/functions.sh

function retry() {
    local i
    for ((i=0; i<5; ++i)) ; do
        if $@ ; then
            break
        fi
        sleep 5
    done
    if [[ $i == 5 ]]; then
        return 1
    fi
}

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
    sudo yum install -y docker device-mapper-libs device-mapper-event-libs
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

ensure_root

echo
echo '[docker install]'
echo "$DISTRO detected"

if ! which docker >/dev/null 2>&1 ; then
    [ "$DISTRO" == "ubuntu" ] || systemctl stop firewalld || true
    install_docker_$DISTRO
    [ "$DISTRO" == "ubuntu" ] || [ "$RHEL_VERSION" == "rhel8" ] || systemctl start docker
else
  echo "docker installed: $(docker --version)"
fi

echo
echo '[docker config]'

if [[ -z "${CONTAINER_REGISTRY}" ]]; then
    echo "${CONTAINER_REGISTRY} is not defined."
    exit
elif ! is_registry_insecure "$CONTAINER_REGISTRY" ; then
    echo "${CONTAINER_REGISTRY} is secure. exit"
    exit
fi

if [ -e "/etc/sysconfig/docker" ]; then
    INSECURE_REGISTRIES=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
    echo "INFO: current /etc/sysconfig/docker insecure_registries=$INSECURE_REGISTRIES"
else
    INSECURE_REGISTRIES=""
fi

DOCKER_CONFIG=$([[ "$RHEL_VERSION" == "rhel8" ]] && echo "/etc/containers/registries.conf" || echo $([[ -z $INSECURE_REGISTRIES ]] && echo "/etc/docker/daemon.json" || echo "/etc/sysconfig/docker" ))

if [ -e $DOCKER_CONFIG ] && grep -q $CONTAINER_REGISTRY $DOCKER_CONFIG; then
    if [ "$DOCKER_CONFIG" == "rhel8" ]; then
        echo "INFO:  rhel8 /etc/containers/registries.conf bug fix"
        INSECURE_REGISTRIES="registries =[$( sed -n '/registries.insecure/{n; s/registries = //p}' "$DOCKER_CONFIG" | tr -d '[]' | sed -r 's/ \+/ /g' | sed 's/ /,/g' )]"
        sudo sed -i "/registries.insecure/{n; s/registries = .*$/${INSECURE_REGISTRIES}/g}" ${DOCKER_CONFIG}
    fi

    echo "Registry $CONTAINER_REGISTRY is configured in $DOCKER_CONFIG. Skip."
    exit 0
fi

if [ ! -e $DOCKER_CONFIG ]; then
    touch $DOCKER_CONFIG
fi

if [ "$DOCKER_CONFIG" == "/etc/sysconfig/docker" ]; then
    echo "plan A [$DOCKER_CONFIG]"
    echo "INFO: add CONTAINER_REGISTRY=$CONTAINER_REGISTRY to insecure list"
    INSECURE_REGISTRIES+=" --insecure-registry $CONTAINER_REGISTRY"
    sudo sed -i '/^INSECURE_REGISTRY/d' "$DOCKER_CONFIG"
    echo "INSECURE_REGISTRY=\"$INSECURE_REGISTRIES\""  | sudo tee -a "$DOCKER_CONFIG"
    sudo cat "$DOCKER_CONFIG"
elif [ "$DOCKER_CONFIG" == "/etc/docker/daemon.json" ]; then
    echo "plan B [$DOCKER_CONFIG]"
    python <<EOF
import json
data=dict()
try:
  with open("${DOCKER_CONFIG}") as f:
    data = json.load(f)
except Exception:
  pass

data.setdefault('insecure-registries', list()).append("${CONTAINER_REGISTRY}")

data['live-restore'] = True
with open("${DOCKER_CONFIG}", 'w') as f:
  data = json.dump(data, f, sort_keys=True, indent=4)
EOF
elif [ "$DOCKER_CONFIG" == "/etc/containers/registries.conf" ]; then
    echo "plan C [$DOCKER_CONFIG]"
    INSECURE_REGISTRIES+="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$DOCKER_CONFIG" | tr -d '[]')"
    echo "INFO: old registries are $INSECURE_REGISTRIES"
    INSECURE_REGISTRIES="registries =[$(echo "$INSECURE_REGISTRIES'$CONTAINER_REGISTRY' " | sed -r 's/ \+/,/g' | sed 's/,\+/,/g' )]"
    echo "INFO: new registries are $INSECURE_REGISTRIES"
    sudo sed -i "/registries.insecure/{n; s/registries = .*$/${INSECURE_REGISTRIES}/g}" ${DOCKER_CONFIG}
else
    echo "plan D [$DOCKER_CONFIG] bad news"
    echo "ERROR: incorrect insecure registries' file '$DOCKER_CONFIG'"
fi

echo
echo '[restart docker]'

if [ x"$DISTRO" == x"centos" -o x"$DISTRO" == x"rhel" ] ; then
    [ "$RHEL_VERSION" == "rhel8" ] || systemctl restart docker
elif [ x"$DISTRO" == x"ubuntu" ]; then
    service docker reload
else
    echo "ERROR: unknown distro $DISTRO"
    exit 1
fi

