#!/bin/bash -e
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export CONTROLLERS_COUNT=${CONTROLLERS_COUNT:-"$(echo $CONTROLLER_NODES | awk -F ' ' '{print NF}')"}

function ziu_1() {
  local zius_1="$( juju status | grep -o 'ziu is in progress - stage\/done = 0\/None' | wc -l)"
  echo "[ziu_test] ziu stage 1: $zius_1"
  return "$(( $zius_1 - $(( CONTROLLER_NODES_COUNT * 3)) ))"
}

function ziu_2() {
  local zius_2="$( juju status | grep -o 'ziu is in progress - stage\/done = 5\/5' | wc -l)"
  echo "[ziu_test] ziu stage 2: $zius_2"
  return "$(( $zius_2 - $(( CONTROLLER_NODES_COUNT*3)) ))"
}

function wait_cmd_success() {
  # silent mode = don't print output of input cmd for each attempt.
  echo "[wait_cmd_success]"
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}

  local state_save=$(set +o)
  set +o xtrace
  set -o pipefail
  local i=0
  while "$(cmd)" != 0; do
    printf "."
    i=$((i + 1))
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $(($i*$interval))s"
      eval "$cmd"
      eval "$state_save"
      return 1
    fi
    sleep $interval
  done
  echo ""
  echo "INFO: done in $((i*10))s"
  eval "$state_save"
}

echo "[ziu_test]"
echo "[ziu_test]  CONTROLLER_NODES: $CONTROLLER_NODES"
echo "[ziu_test]  CONTROLLERS_COUNT: $CONTROLLERS_COUNT"
echo "[ziu_test]  juju run-action contrail-controller/leader upgrade-ziu"
juju run-action contrail-controller/leader upgrade-ziu
# All services of control plane (controller, analytics, analyticsdb) go to the maintenance mode

wait_cmd_success ziu_1 10 10
echo "[ziu_test]  juju config"
juju config contrail-analytics image-tag=latest
juju config contrail-analyticsdb image-tag=latest
juju config contrail-agent image-tag=latest
juju config contrail-openstack image-tag=latest
juju config contrail-controller image-tag=latest
# wait for all charms are in stage 5/5 about 40 minutes.

wait_cmd_success ziu_2 20 60
echo "[ziu_test]  juju run-action contrail-agent/0 upgrade"
juju run-action contrail-agent/0 upgrade
# Wait for success about 5 minutes - please check output of action and juju status
