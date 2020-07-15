#!/bin/bash -e
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export PATH=$PATH:/snap/bin
export CONTROLLERS_COUNT=${CONTROLLERS_COUNT:-"$(echo $CONTROLLER_NODES | awk -F ',' '{print NF}')"}
status_nodes=$(( CONTROLLER_NODES_COUNT*3))
function ziu_it() {
    local zius_it="$( $(which juju) status | grep -io '$1' | wc -l)"
    echo "[ziu_test] ziu stage \"$1\": $zius_it"
    return "$(( $zius_it - $status_nodes ))"
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
  while ziu_it "$cmd" != 0; do
    #printf "."
    printf "$i"
    i=$((i + 1))
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $(($i*$interval))s"
      #eval "$cmd"
      echo "error juju status"
      juju status
      echo "----------------------------------------"
      eval ziu_it
      eval "$state_save"
      exit 1
    fi
    sleep $interval
  done
  echo "successful juju status"
  juju status
  echo "----------------------------------------"
  echo "INFO: done in $(($i*$interval))s"
  eval "$state_save"
}

echo "[ziu_test]  CONTROLLER_NODES: $CONTROLLER_NODES"
echo "[ziu_test]  CONTROLLERS_COUNT: $CONTROLLERS_COUNT"
echo "[ziu_test]  juju run-action contrail-controller/leader upgrade-ziu"

juju run-action contrail-controller/leader upgrade-ziu
# All services of control plane (controller, analytics, analyticsdb) go to the maintenance mode

wait_cmd_success "ziu is in progress - stage\/done = 0\/None" 10 20
echo "[ziu_test]  juju config"

juju config contrail-analytics image-tag=nightly-master
juju config contrail-analyticsdb image-tag=nightly-master
juju config contrail-agent image-tag=nightly-master
juju config contrail-openstack image-tag=nightly-master
juju config contrail-controller image-tag=nightly-master
# wait for all charms are in stage 5/5 about 40 minutes.

wait_cmd_success "ziu is in progress - stage\/done = 5\/5" 10 360
echo "[ziu_test]  juju run-action contrail-agent/0 upgrade"
juju run-action contrail-agent/0 upgrade
juju status
# Wait for success about 5 minutes - please check output of action and juju status
#export CONTRAIL_CONTAINER_TAG=nightly-master
#export CONTAINER_REGISTRY=nexus.jenkins.progmaticlab.com:5002
