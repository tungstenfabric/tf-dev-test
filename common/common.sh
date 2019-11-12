#!/bin/bash

[[ "$DEBUG" == 'true' ]] && set -x

set -o errexit

# test options
export TF_TEST_NAME=${TF_TEST_NAME:-"smoke-test"}
export TF_TEST_IMAGE=${TF_TEST_IMAGE:-"${TF_TEST_NAME}:latest"}

# working environment
WORKSPACE=${WORKSPACE:-$(pwd)}
TF_CONFIG_DIR="${WORKSPACE}/.tf"
TF_STACK_PROFILE="${TF_CONFIG_DIR}/stack.env"

# import tf profile that created by devstack into current context
[ -e "$TF_STACK_PROFILE" ] && source "$TF_STACK_PROFILE"

# determined variables
DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
PHYS_INT=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
NODE_IP=`ip addr show dev $PHYS_INT | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`

# defaults for containers
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-'tungstenfabric'}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-'latest'}

# defaults stack
export ORCHESTRATOR=${ORCHESTRATOR:-"kubernetes"}
export CONTROLLER_NODES=${CONTROLLER_NODES:-$NODE_IP}
export AGENT_NODES=${AGENT_NODES:-$NODE_IP}

# Openstack defaults
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-"queens"}
