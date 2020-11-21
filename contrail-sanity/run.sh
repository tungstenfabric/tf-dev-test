#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}
export IMAGE_WEB_SERVER=${IMAGE_WEB_SERVER-"tf-nexus.progmaticlab.com/repository/"}
export SSH_USER=${SSH_USER:-$(whoami)}
export ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

[ "$DISTRO" == "rhel" ] && export RHEL_VERSION="rhel$( cat /etc/redhat-release | egrep -o "[0-9]*\." | cut -d '.' -f1 )"

# RHOSP16's 'docker --> podman' symlink for overcloud nodes
if [ "$RHEL_VERSION" == "rhel8" ] ; then
    for ip in $(echo "$CONTROLLER_NODES $AGENT_NODES $OPENSTACK_CONTROLLER_NODES" | sort -u) ; do
        ssh $ssh_opts $SSH_USER@$ip "sudo yum install -y podman-docker && sudo touch /etc/containers/nodocker"
    done
fi
#
if [ -z "$TF_TEST_IMAGE" ] ; then
    TF_TEST_IMAGE="contrail-test-test:${CONTRAIL_CONTAINER_TAG}"
    [ -n "$CONTAINER_REGISTRY" ] && TF_TEST_IMAGE="${CONTAINER_REGISTRY}/${TF_TEST_IMAGE}"
else
    echo "INFO: TF_TEST_IMAGE=$TF_TEST_IMAGE"
    # let's suppose that $TF_TEST_IMAGE contains registry before first '/'
    # if it's not registry - it can be namespace. in this case it will not be treated
    # as insecure registry and will not be added to docker's config
    export CONTAINER_REGISTRY="$(echo $TF_TEST_IMAGE | cut -d '/' -f 1)"
fi

echo 'INFO: [ensure python3 is present]'
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

python3 -m pip --version || curl -s https://bootstrap.pypa.io/get-pip.py | sudo python3
sudo python3 -m pip install jinja2 future

if echo ",${CONTROLLER_NODES},${AGENT_NODES}," | tr ' ' ','  | grep -q ",${NODE_IP}," ; then
    # prepare ssh keys for local connect
    set_ssh_keys $SSH_USER
fi

# get testrunner.sh project
echo "INFO: get testrunner.sh from image"
sudo docker pull $TF_TEST_IMAGE
tmp_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
sudo docker create --name $tmp_name $TF_TEST_IMAGE
sudo docker cp $tmp_name:/contrail-test/testrunner.sh ./testrunner.sh
sudo docker rm $tmp_name

# hack for tf-test container. it goes to the host over ftp and downloads /etc/kubernetes/admin.conf by default
if [[ ${TF_TEST_TARGET} == *"ci_k8s_sanity"* ]]; then
    echo "INFO: apply hack for kube config"
    # this copy into /tmp/ is only required to let tf-test to copy it into its container, load and parse
    # all calls to kubectl from tf-test will be done with default config on node
    #
    # ansible and kubespray deployments (k8s-manifests and helm) -
    #   kubespray has /etc/kubernetes/admin.conf on each master
    #   ansible has it just on one node - it can be any node from controller_nodes
    #   tf-test walks through controller_nodes (node with role k8s_master) and can copy
    #   this config from any node also. we have to set permissions for all
    #
    # juju has own way - config is in $HOME/.kube/config and only on worker nodes
    #   master nodes works without config - with localhost:8080
    #   to let tf-test to copy this config, load and parse let's copy it from worker to master
    KUBE_CONFIG="/tmp/kube_config"
    if [[ "$DEPLOYER" == 'juju' ]]; then
        src_ip=$(echo $AGENT_NODES | awk '{print $1}')
        dst_ip=$(echo $CONTROLLER_NODES | awk '{print $1}')
        echo "INFO: juju branch. copy from $src_ip/.kube/config to $dst_ip:$KUBE_CONFIG"
        scp $ssl_opts $SSH_USER@$src_ip:.kube/config $KUBE_CONFIG
        scp $KUBE_CONFIG $ssl_opts $SSH_USER@$dst_ip:$KUBE_CONFIG
    else
        config="/etc/kubernetes/admin.conf"
        echo "INFO: ansible/kubespray branch - try to find config in $config"
        for ip in ${CONTROLLER_NODES} ; do
            echo "INFO: node $ip"
            ssh $ssh_opts $SSH_USER@$ip "sudo bash -cx 'ls -la /etc/kubernetes ; ls -la .kube'" || /bin/true
            ssh $ssh_opts $SSH_USER@$ip "sudo bash -cx 'cp -f $config $KUBE_CONFIG && chmod 644 $KUBE_CONFIG'" || /bin/true
        done
    fi
    export KUBE_CONFIG
fi

# run tests:

echo "INFO: prepare input parameters from template $TF_TEST_INPUT_TEMPLATE"
"$my_dir/../common/jinja2_render.py" < $TF_TEST_INPUT_TEMPLATE > ./contrail_test_input.yaml

echo "INFO: TF test input:"
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

echo "INFO: run tests..."

# NOTE: testrunner.sh always returns non-zero code even if it's SUCCESS...
res=0
if HOME=$WORKSPACE ./testrunner.sh run -H \
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
        res=1
    fi
fi

echo "INFO: collect logs"
testdir=$(ls -1 contrail-test-runs | sort | tail -1)
pushd contrail-test-runs/$testdir
tar -czvf $WORKSPACE/logs.tgz logs
cd reports
tar -rzvf $WORKSPACE/logs.tgz *
popd

exit $res
