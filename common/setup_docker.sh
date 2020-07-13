#!/bin/bash -e

scriptdir=$(realpath $(dirname "$0"))
source ${scriptdir}/common.sh
source ${scriptdir}/functions.sh

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

[ ! -e /etc/docker/daemon.json ] && touch /etc/docker/daemon.json
if [[ -n "${CONTAINER_REGISTRY}" ]] ; then
  python <<EOF
import json
data=dict()
try:
  with open('/etc/docker/daemon.json') as f:
    data = json.load(f)
except Exception:
  pass

data.setdefault('insecure-registries', list()).append("${CONTAINER_REGISTRY}")

data['live-restore'] = True
with open('/etc/docker/daemon.json', 'w') as f:
  data = json.dump(data, f, sort_keys=True, indent=4)
EOF
else
    echo "${CONTAINER_REGISTRY} is not defined. exit"
    exit 1
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
