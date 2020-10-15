#!/bin/bash -e

# TODO: extract juju part to separate file and support rhosp in similar way

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export PATH=$PATH:/snap/bin

CONTROLLERS_COUNT=`echo "$( echo $CONTROLLER_NODES | tr ',' ' ' )" | awk -F ' ' '{print NF}'`
status_nodes=$(( $CONTROLLERS_COUNT * 3 ))

function ziu_it() {
  local zius_it=$(juju status | grep "$1" | wc -l)
  current_status="$(( $zius_it - $status_nodes ))"
}

function wait_cmd_success() {
  i=0
  current_status=1

  while [ $current_status -ne 0 ]; do
    printf "."
    i=$((i + 1))
    if (( i > $3 )) ; then
      echo -e "\nERROR: wait failed in $((i*$2))s"
      exit 1
    fi
    sleep $2
    ziu_it "$1"
  done

  echo -e "\nINFO: done in $((i*$2))s"
}

juju run-action contrail-controller/leader upgrade-ziu

wait_cmd_success "ziu is in progress - stage\/done = 0\/None" 10 60

juju config contrail-analytics image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-analyticsdb image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-agent image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-openstack image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-controller image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY

wait_cmd_success "ziu is in progress - stage\/done = 5\/5" 10 540

for agent in $(juju status | grep -o "contrail-agent/[0-9]*"); do
  juju run-action --wait $agent upgrade
done

i=1
while true; do
  printf "."
  status="$(juju status)"
  if [[ $status =~ "ziu" ]]; then
    i=$((i + 1))
    if (( i > 62 )) ; then
      echo "ERROR: ziu is still in progress after 120s"
      exit 1
    fi
  else
    echo -e "\nINFO:  done in $((i*10))"
    break
  fi
  sleep 10
done

# to wait while all agents come back and show active state (otherwise we catch sometimes NTP state unsynchronised) 
# TODO: change to something like wait_for_active
sleep 120
