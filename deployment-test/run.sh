#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

rm -f $WORKSPACE/logs.tgz || /bin/true

if [ -z "$TF_DEPLOYMENT_TEST_IMAGE" ] ; then
    TF_DEPLOYMENT_TEST_IMAGE="tf-deployment-test:${CONTRAIL_CONTAINER_TAG}"
    [ -n "$CONTAINER_REGISTRY" ] && TF_DEPLOYMENT_TEST_IMAGE="${CONTAINER_REGISTRY}/${TF_DEPLOYMENT_TEST_IMAGE}"
else
    echo "INFO: TF_DEPLOYMENT_TEST_IMAGE=$TF_DEPLOYMENT_TEST_IMAGE"
    # let's suppose that $TF_DEPLOYMENT_TEST_IMAGE contains registry before first '/'
    # if it's not registry - it can be namespace. in this case it will not be treated
    # as insecure registry and will not be added to docker's config
    export CONTAINER_REGISTRY="$(echo $TF_DEPLOYMENT_TEST_IMAGE | cut -d '/' -f 1)"
fi

install_prerequisites_$DISTRO

# prepare env
sudo -E $my_dir/../common/setup_docker.sh

# prepare ssl certs
if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
    echo "INFO: SSL enabled. prepare certs from env if exist"
    sudo mkdir -p /etc/contrail/ssl/private /etc/contrail/ssl/certs
    if [[ -n "$SSL_KEY" ]]; then
        echo "$SSL_KEY" | base64 -d -w 0 | sudo tee /etc/contrail/ssl/private/server-privkey.pem > /dev/null
    fi
    if [[ -n "$SSL_CERT" ]]; then
        echo "$SSL_CERT" | base64 -d -w 0 | sudo tee /etc/contrail/ssl/certs/server.pem > /dev/null
    fi
    if [[ -n "$SSL_CACERT" ]]; then
        echo "$SSL_CACERT" | base64 -d -w 0 | sudo tee /etc/contrail/ssl/certs/ca-cert.pem > /dev/null
    fi
fi

cd $WORKSPACE

# get testrunner.sh project
echo "INFO: get testrunner.sh from image"
if ! sudo docker pull $TF_DEPLOYMENT_TEST_IMAGE ; then
  echo "INFO: looks like deployment-test container was not built due to old release. Skipping tests..."
  exit
fi

tmp_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
sudo docker create --name $tmp_name $TF_DEPLOYMENT_TEST_IMAGE
sudo docker cp $tmp_name:/testrunner.sh ./testrunner.sh
sudo docker rm $tmp_name

# run tests
echo "INFO: run tests..."
./testrunner.sh
