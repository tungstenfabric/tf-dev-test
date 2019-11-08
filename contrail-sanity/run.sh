#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

# 
TF_TEST_NAME="contrail-test"
TF_TEST_IMAGE="${TF_TEST_NAME}-test:$CONTRAIL_CONTAINER_TAG"

TF_TEST_PROJECT="Juniper/$TF_TEST_NAME.git"
TF_TEST_TARGET=${TF_TEST_TARGET:-'ci_k8s_sanity'}
TF_TEST_INPUT_TEMPLATE=${TF_TEST_INPUT_TEMPLATE:-"$my_dir/contrail_test_input.$ORCHESTRATOR.yaml.j2"}

pushd $WORKSPACE

echo 
echo "[$TF_TEST_NAME]"

# prerequisites
# (expected pip is already installed)
pip install docker-py

# get test project
echo get $TF_TEST_NAME project
[ -d ./$TF_TEST_NAME ] &&  rm -rf ./$TF_TEST_NAME
git clone --depth 1 --single-branch https://github.com/$TF_TEST_PROJECT

# run tests:

echo "prepare input parameters from template $TF_TEST_INPUT_TEMPLATE"
python3 "$my_dir/jinja2_render.py" < $TF_TEST_INPUT_TEMPLATE > ./contrail_test_input.yaml

echo "TF test input:"
cat ./contrail_test_input.yaml

echo "run tests"

time EXTRA_RUN_TEST_ARGS="-t" sudo -E ./testrunner.sh run \
    -P ./contrail_test_input.yaml \
    -k ~/.ssh/id_rsa \
    -f $TF_TEST_TARGET \
    $TF_TEST_IMAGE

popd

# check for failures
[ x\"$(grep testsuite /root/contrail-test-runs/*/reports/TESTS-TestSuites.xml  | grep -o  'failures=\\S\\+' | uniq)\" = x'failures=\"0\"' ]
exit $?
