#!/bin/bash -e
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export PATH=$PATH:/snap/bin

export CONTROLLERS_COUNT=`echo "$( echo $CONTROLLER_NODES | tr ',' ' ' )" | awk -F ' ' '{print NF}'`
export status_nodes=$(( $CONTROLLERS_COUNT * 3 ))
export current_status=1

function ziu_it() {
    local zius_it=$( $(which juju) status | grep "$1" | wc -l)
    current_status="$(( $zius_it - $status_nodes ))"
}

function wait_cmd_success() {
  # silent mode = don't print output of input cmd for each attempt.
  local cmd_arg=$1
  local interval=${2:-10}
  local max=${3:-360}

  local state_save=$(set +o)
  set +o xtrace
  set -o pipefail
  local i=0
  current_status=1
  while [ $current_status -ne 0 ]; do
    printf "."
    i=$((i + 1))
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $((i*interval))s"
      eval ziu_it "$cmd_arg"
      eval "$state_save"
      exit 1
    fi
    sleep $interval
    ziu_it "$cmd_arg"
  done
  echo ""
  echo "INFO: done in $((i*interval))s"
  eval "$state_save"
}

juju run-action contrail-controller/leader upgrade-ziu
# All services of control plane (controller, analytics, analyticsdb) go to the maintenance mode

wait_cmd_success "ziu is in progress - stage\/done = 0\/None" 10 60

juju config contrail-analytics image-tag=nightly-master
juju config contrail-analyticsdb image-tag=nightly-master
juju config contrail-agent image-tag=nightly-master
juju config contrail-openstack image-tag=nightly-master
juju config contrail-controller image-tag=nightly-master
# wait for all charms are in stage 5/5 about 40 minutes.

wait_cmd_success "ziu is in progress - stage\/done = 5\/5" 10 540

i=0
while [ $i -lt $CONTROLLERS_COUNT ]; do
    juju run-action --wait contrail-agent/$i upgrade
    i=$((i + 1))
done

i=0
status=`juju status`

while [  ]; do
    printf "."
    if [[ $status =~ "ziu" ]]; then
      i=$((i + 1))
    else
        echo ""
        echo "INFO:  done in $((i*10))"
        break
    fi
    sleep 10
done


# Wait for success about 5 minutes - please check output of action and juju status

#export CONTRAIL_CONTAINER_TAG=nightly-master
#export CONTAINER_REGISTRY=nexus.jenkins.progmaticlab.com:5002
