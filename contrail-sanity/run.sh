#!/bin/bash -e

[[ "$DEBUG" == 'true' ]] && set -x
set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}
export IMAGE_WEB_SERVER=${IMAGE_WEB_SERVER-"nexus.jenkins.progmaticlab.com/repository/"}
export SSH_USER=${SSH_USER:-$(whoami)}

[ "$DISTRO" == "rhel" ] && export RHEL_VERSION="rhel$( cat /etc/redhat-release | egrep -o "[0-9]*\." | cut -d '.' -f1 )"

#
if [ -z "$TF_TEST_IMAGE" ] ; then
    TF_TEST_IMAGE="contrail-test-test:${CONTRAIL_CONTAINER_TAG}"
    [ -n "$CONTAINER_REGISTRY" ] && TF_TEST_IMAGE="${CONTAINER_REGISTRY}/${TF_TEST_IMAGE}"
else
    echo "DEBUG:  TF_TEST_IMAGE=$TF_TEST_IMAGE"
    # TODO:
    # in this case it's registry should be added as INSECURE
fi

echo '[ensure python is present]'
install_prerequisites_$DISTRO

# prepare env
sudo -E $my_dir/../common/setup_docker.sh

k8s_target='ci_k8s_sanity'
if [[ "$DEPLOYER" == 'openshift' ]] ; then
  k8s_target='ci_openshift'
fi
declare -A default_targets=(['kubernetes']="$k8s_target" ['openstack']='ci_sanity' ['all']="ci_sanity,${k8s_target}")
TF_TEST_TARGET=${TF_TEST_TARGET:-${default_targets[$ORCHESTRATOR]}}
if [[ -z "$TF_TEST_TARGET" ]]; then
  echo "ERROR: please provide either ORCHESTRATOR or TF_TEST_TARGET"
  exit 1
fi
echo "INFO: test_target is $TF_TEST_TARGET"
TF_TEST_INPUT_TEMPLATE=${TF_TEST_INPUT_TEMPLATE:-"$my_dir/contrail_test_input.yaml.j2"}

cd $WORKSPACE

echo
echo "[tf-test]"

curl -s https://bootstrap.pypa.io/get-pip.py | sudo python
sudo python -m pip install jinja2 future

if echo ",${CONTROLLER_NODES},${AGENT_NODES}," | tr ' ' ','  | grep -q ",${NODE_IP}," ; then
    # prepare ssh keys for local connect
    set_ssh_keys $SSH_USER
fi

# get testrunner.sh project
echo "get testrunner.sh"
sudo docker pull $TF_TEST_IMAGE
tmp_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
sudo docker create --name $tmp_name $TF_TEST_IMAGE
sudo docker cp $tmp_name:/contrail-test/testrunner.sh ./testrunner.sh
sudo docker rm $tmp_name

# run tests:

echo "prepare input parameters from template $TF_TEST_INPUT_TEMPLATE"
"$my_dir/../common/jinja2_render.py" < $TF_TEST_INPUT_TEMPLATE > ./contrail_test_input.yaml

echo "TF test input:"
cat ./contrail_test_input.yaml

ssl_opts=''
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
    ssl_opts='-l /etc/contrail/ssl'
fi

# hack for contrail-test container. it goes to the host over ftp and downloads /etc/kubernetes/admin.conf
# TODO: fix this in contrail-test
if [[ ${TF_TEST_TARGET} == "ci_k8s_sanity" ]] ; then
  if [[ ! -f /etc/kubernetes/admin.conf && -f ~/.kube/config ]] ; then
    sudo mkdir -p /etc/kubernetes/
    sudo cp ~/.kube/config /etc/kubernetes/admin.conf
  fi
  sudo chmod 644 /etc/kubernetes/admin.conf || /bin/true
fi

echo "run tests..."

# NOTE: testrunner.sh always returns non-zero code even if it's SUCCESS...
if HOME=$WORKSPACE ./testrunner.sh run \
    -P ./contrail_test_input.yaml \
    -k ~/.ssh/id_rsa \
    $ssl_opts \
    -T $TF_TEST_TARGET \
    $TF_TEST_IMAGE ; then

    echo "WOW! testrunner exited with code 0!"
else
    # NOTE: same hack as in zuul for now
    test_failures="$(grep testsuite ${WORKSPACE}/contrail-test-runs/*/reports/TESTS-TestSuites.xml | grep -o  'failures=\S\+' | uniq)"
    if [[ x"$test_failures" != x'failures="0"' ]]; then
        echo "ERROR: there were failures during the test."
        echo "       See detailed logs in ${WORKSPACE}/contrail-test-runs"
        exit 1
    fi
fi
