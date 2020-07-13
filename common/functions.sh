#!/bin/bash

function wait_cmd_success() {
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent=${4:-1}
  local i=0
  while ! eval "$cmd" 2>/dev/null; do
      if [[ "$silent" != "0" ]]; then
        printf "."
      fi
      i=$((i + 1))
      if (( i > max )) ; then
        return 1
      fi
      sleep $interval
  done
  return 0
}

function run_container() {
  local name=$1
  local image$2
  shift 2
  local opts=$@
  sudo docker run --name $name -it --rm --network host --privileged \
    -e WORKSPACE=$WORKSPACE \
    -v $WORKSPACE:$WORKSPACE \
    -v "/var/run:/var/run" \
    $opts $image
  return $?
}

function set_ssh_keys_current_user() {
  echo "set ssh options for $(whoami) user"
  [ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
  [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
  [ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
  grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  cat <<EOF > ~/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chmod 600 ~/.ssh/config
}

function set_ssh_keys() {
  local user=${1:-}
  if [[ -z "$user" || "$user" == "$(whoami)" ]] ; then
    # set for current user
    set_ssh_keys_current_user
  elif [[ "$user" == 'root' ]] ; then
    # set for root if current is not root
    # contrail-test use root for now
    sudo bash -c "$(declare -f set_ssh_keys_current_user); set_ssh_keys_current_user"
  else
    sudo runuser -u $user "$(declare -f set_ssh_keys_current_user); set_ssh_keys_current_user"
  fi
}

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
  if [[ "$ENABLE_RHSM_REPOS" == "true" ]]; then
    subscription-manager repos \
      --enable rhel-7-server-extras-rpms \
      --enable rhel-7-server-optional-rpms
  fi
  retry yum install -y docker device-mapper-libs device-mapper-event-libs
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
    echo "       mysudo -E $0"
    return 1
  fi
}

function install_prerequisites_centos() {
  local pkgs=""
  which lsof || pkgs+=" lsof"
  which python || pkgs+=" python"
  if [ -n "$pkgs" ] ; then
    mysudo yum install -y $pkgs
  fi
}

function install_prerequisites_rhel() {
  install_prerequisites_centos
}

function install_prerequisites_ubuntu() {
  local pkgs=""
  which lsof || pkgs+=" lsof"
  which python || pkgs+=" python-minimal"
  if [ -n "$pkgs" ] ; then
    export DEBIAN_FRONTEND=noninteractive
    mysudo -E apt-get install -y $pkgs
  fi
}
