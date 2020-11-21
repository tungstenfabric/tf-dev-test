#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

rm -f $WORKSPACE/logs.tgz

if [ -z "$TF_TEST_IMAGE" ] ; then
    TF_TEST_IMAGE="tf-deployment-test:${CONTRAIL_CONTAINER_TAG}"
    [ -n "$CONTAINER_REGISTRY" ] && TF_TEST_IMAGE="${CONTAINER_REGISTRY}/${TF_TEST_IMAGE}"
else
    echo "INFO: TF_TEST_IMAGE=$TF_TEST_IMAGE"
    # let's suppose that $TF_TEST_IMAGE contains registry before first '/'
    # if it's not registry - it can be namespace. in this case it will not be treated
    # as insecure registry and will not be added to docker's config
    export CONTAINER_REGISTRY="$(echo $TF_TEST_IMAGE | cut -d '/' -f 1)"
fi

# prepare env
sudo -E $my_dir/../common/setup_docker.sh

cd $WORKSPACE

# get testrunner.sh project
echo "INFO: get testrunner.sh from image"
sudo docker pull $TF_TEST_IMAGE
tmp_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
sudo docker create --name $tmp_name $TF_TEST_IMAGE
sudo docker cp $tmp_name:/testrunner.sh ./testrunner.sh
sudo docker rm $tmp_name

# run tests
echo "INFO: run tests..."
./testrunner.sh
