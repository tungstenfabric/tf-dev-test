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

function install_prerequisites_centos() {
    local pkgs=""
    which lsof || pkgs+=" lsof"
    which python || pkgs+=" python"
    if [ -n "$pkgs" ] ; then
        sudo yum install -y $pkgs
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
        sudo -E apt-get install -y $pkgs
    fi
}
