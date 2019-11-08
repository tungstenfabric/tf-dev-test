#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common/common.sh"
source "$my_dir/common/functions.sh"

pushd $WORKSPACE

echo 
echo "[$TF_TEST_NAME]"

nodes="$(echo ${CONTROLLER_NODES},${AGENT_NODES} | tr ',' '\n' | sort | uniq)"

# TODO: to be implemented
#sudo contrail-status

# run_container $TF_TEST_NAME $TF_TEST_IMAGE
res=$?

popd

exit $res
