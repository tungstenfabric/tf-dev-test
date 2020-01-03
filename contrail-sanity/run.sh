#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}
export IMAGE_WEB_SERVER=${IMAGE_WEB_SERVER-"pnexus.sytes.net/repository/"}
export SSH_USER=${SSH_USER:-$(whoami)}

# 
TF_TEST_NAME="contrail-test"
if [ -z "$TF_TEST_IMAGE" ] ; then
    TF_TEST_IMAGE="${TF_TEST_NAME}-test:${OPENSTACK_VERSION}-${CONTRAIL_CONTAINER_TAG}"
    [ -n "$CONTAINER_REGISTRY" ] && TF_TEST_IMAGE="${CONTAINER_REGISTRY}/${TF_TEST_IMAGE}"
fi

TF_TEST_PROJECT="Juniper/$TF_TEST_NAME.git"
declare -A default_targets=(['kubernetes']='ci_k8s_sanity' ['openstack']='ci_sanity')
TF_TEST_TARGET=${TF_TEST_TARGET:-${default_targets[$ORCHESTRATOR]}}
if [[ -z "$TF_TEST_TARGET" ]]; then
  echo "ERROR: please provide either ORCHESTRATOR or TF_TEST_TARGET"
  exit 1
fi
echo "INFO: test_target is $TF_TEST_TARGET"
TF_TEST_INPUT_TEMPLATE=${TF_TEST_INPUT_TEMPLATE:-"$my_dir/contrail_test_input.$ORCHESTRATOR.yaml.j2"}

cd $WORKSPACE

echo 
echo "[$TF_TEST_NAME]"

curl -s https://bootstrap.pypa.io/get-pip.py | sudo python
sudo pip install jinja2

# prepare ssh keys for local connect
set_ssh_keys $SSH_USER

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

# hack for contrail-test container. it goes to the host over ftp and downloads /etc/kubernetes/admin.conf
# TODO: fix this in contrail-test
sudo chmod 644 /etc/kubernetes/admin.conf || /bin/true

echo "run tests..."

# NOTE: testrunner.sh always returns non-zero code even if it's SUCCESS...
if HOME=$WORKSPACE ./testrunner.sh run \
    -P ./contrail_test_input.yaml \
    -k ~/.ssh/id_rsa \
    -f $TF_TEST_TARGET \
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
