#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

pushd $WORKSPACE

echo 
echo "[$TF_TEST_NAME]"

# TODO: to be implemented

printf '%*s\n' 120 | tr ' ' '='
sudo contrail-status
printf '%*s\n' 120 | tr ' ' '='
sudo docker ps -a
printf '%*s\n' 120 | tr ' ' '='
sudo docker images
printf '%*s\n' 120 | tr ' ' '*'
ps ax -H
printf '%*s\n' 120 | tr ' ' '*'

if [[ "$ORCHESTRATOR" == "openstack" ]]; then
  ${my_dir}/test_openstack_vm.sh
fi

${my_dir}/test_webui.sh
