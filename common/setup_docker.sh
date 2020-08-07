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
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
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
  yum install -y docker device-mapper-libs device-mapper-event-libs
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
  if [ x"$DISTRO" == x"centos" ]; then
    systemctl stop firewalld || true
    install_docker_centos
    systemctl start docker
  #  grep 'dm.basesize=20G' /etc/sysconfig/docker-storage || sed -i 's/DOCKER_STORAGE_OPTIONS=/DOCKER_STORAGE_OPTIONS=--storage-opt dm.basesize=20G /g' /etc/sysconfig/docker-storage
  #  systemctl restart docker
  elif [ x"$DISTRO" == x"rhel" ]; then
    systemctl stop firewalld || true
    install_docker_rhel
    systemctl start docker
  elif [ x"$DISTRO" == x"ubuntu" ]; then
    install_docker_ubuntu
  fi
else
  echo "docker installed: $(docker --version)"
fi

echo
echo '[docker config]'

if [[ -z "${CONTAINER_REGISTRY}" ]]; then
    echo "${CONTAINER_REGISTRY} is not defined."
    exit
fi

if is_registry_insecure "$CONTAINER_REGISTRY"; then
    INSECURE_REGISTRIES=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
    echo "INFO: current /etc/sysconfig/docker insecure_registries=$INSECURE_REGISTRIES"
    DOCKER_CONFIG=$([[ -z $INSECURE_REGISTRIES ]] && echo "/etc/docker/daemon.json" || echo "/etc/sysconfig/docker")

    if [ -e $DOCKER_CONFIG ] && grep -q $CONTAINER_REGISTRY $DOCKER_CONFIG; then
        echo "Registry $CONTAINER_REGISTRY is configured in $DOCKER_CONFIG. Skip."
        exit 0
    fi

    if [ "$DOCKER_CONFIG" == "/etc/sysconfig/docker" ]; then
        echo "INFO: add CONTAINER_REGISTRY=$CONTAINER_REGISTRY to insecure list"
        INSECURE_REGISTRIES+=" --insecure-registry $CONTAINER_REGISTRY"
        sudo sed -i '/^INSECURE_REGISTRY/d' "$DOCKER_CONFIG"
        echo "INSECURE_REGISTRY=\"$INSECURE_REGISTRIES\""  | sudo tee -a "$DOCKER_CONFIG"
        sudo cat "$DOCKER_CONFIG"
    else
        if [ ! -e $DOCKER_CONFIG ]; then
            touch $DOCKER_CONFIG
        fi
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
    fi
else
    echo "${CONTAINER_REGISTRY} is not defined. exit"
    exit
fi

echo
echo '[restart docker]'

if [ x"$DISTRO" == x"centos" -o x"$DISTRO" == x"rhel" ] ; then
    systemctl restart docker
elif [ x"$DISTRO" == x"ubuntu" ]; then
    service docker reload
else
    echo "ERROR: unknown distro $DISTRO"
    exit 1
fi

