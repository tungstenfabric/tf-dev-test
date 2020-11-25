#!/bin/bash -e

# TODO: extract juju part to separate file and support rhosp in similar way

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export PATH=$PATH:/snap/bin

CONTROLLERS_COUNT=`echo "$( echo $CONTROLLER_NODES | tr ',' ' ' )" | awk -F ' ' '{print NF}'`
analyticsdb_enabled=$(( $(juju status | cut -d " " -f1 | grep -q contrail-analyticsdb; echo $?) == 0 ))
status_nodes=$(( $CONTROLLERS_COUNT * (2 + $analyticsdb_enabled) ))

function ziu_status() {
    (( $(juju status | grep "$1" | wc -l) - $status_nodes ))
}

function wait_cmd_success() {
    i=0
    while eval $3; do
        sleep $1
        printf "."
        i=$((i + 1))
        if (( i >= $2 )); then
            echo -e "\nERROR: wait failed in $((i*$1))s"
            exit 1
        fi
    done
    echo -e "\nINFO: done in $((i*$1))s"
}

juju run-action contrail-controller/leader upgrade-ziu

wait_cmd_success 10 60 "ziu_status \"ziu is in progress - stage\/done = 0\/None\""

juju config contrail-analytics image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
(( $analyticsdb_enabled )) && juju config contrail-analyticsdb image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-agent image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-openstack image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY
juju config contrail-controller image-tag=$CONTRAIL_CONTAINER_TAG docker-registry=$CONTAINER_REGISTRY

wait_cmd_success 20 540 "ziu_status \"ziu is in progress - stage\/done = 5\/5\""
# wait a bit when all agents consume stage 5
sleep 60

for agent in $(juju status | grep -o "contrail-agent/[0-9]*"); do
    juju run-action --wait $agent upgrade
done

wait_cmd_success 20 30 "juju status | grep -q \"ziu\""
wait_cmd_success 50 36 "juju status | grep -q \"waiting\|blocked\|maintenance\|unknown\""

