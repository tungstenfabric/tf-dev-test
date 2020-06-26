#!/bin/bash
set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/openrc"

TEST_SUBNET_CIDR="${TEST_SUBNET_CIDR:-172.23.0.0/24}"
TEST_IMAGE_NAME="${TEST_IMAGE_NAME:-cirros}"
TEST_IMAGE_URL=${TEST_IMAGE_URL:-'http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img'}

OVERCLOUD_TLS_OPTS=${OVERCLOUD_TLS_OPTS:-}

SSH_OPTIONS="-T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

TEST_INSTANCE_NAME=tf-devstack-testvm
function cleanup() {
  openstack server delete tf-devstack-testvm --wait || :
  openstack flavor delete m1.micro || :
  openstack security group delete allow_ssh || :
  openstack subnet delete tf-devstack-subnet-test || :
  openstack network delete tf-devstack-test || :
}

function prepare_image() {
  local image_name=${1}
  local output=''
  if ! output=`openstack $OVERCLOUD_TLS_OPTS image show $image_name 2>/dev/null` ; then
    local fn=$(echo "$TEST_IMAGE_URL" | awk -F '/' '{print($NF)}')
    rm -f $fn
    wget -t 2 -T 60 -q "$TEST_IMAGE_URL"
    if ! output=`openstack $OVERCLOUD_TLS_OPTS image create --public --file $fn $image_name` ; then
      return 1
    fi
  fi
  local image_id=`echo "$output" | awk '/ id /{print $4}'`
  echo $image_id
}

# Clean up proactively in case previous attempt failed
cleanup

# Set up
openstack network create tf-devstack-test
openstack subnet create --subnet-range "$TEST_SUBNET_CIDR" --network tf-devstack-test tf-devstack-subnet-test
openstack security group create allow_ssh
openstack security group rule create --dst-port 22 --protocol tcp allow_ssh
openstack flavor create --ram 64 --disk 1 --vcpus 1 m1.micro
image=$(prepare_image $TEST_IMAGE_NAME)

# Deploy
first_hypervisor=$(openstack hypervisor list -f value | grep up | sort | head -n 1)
first_hypervisor_name=$(echo $first_hypervisor | cut -d' ' -f2)
first_hypervisor_ip=$(echo $first_hypervisor | cut -d' ' -f4)
openstack server create --availability-zone "nova::$first_hypervisor_name" --image "$image" --flavor m1.micro --nic net-id=tf-devstack-test --security-group allow_ssh --wait "$TEST_INSTANCE_NAME"

# Ensure connectivity

instance_ip=$(openstack server show $TEST_INSTANCE_NAME | awk '/addresses/{print $4}' | cut -d '=' -f 2 | sed 's/,$//g')
	
# on the hypervisor where instance run
if_name=$(ssh $SSH_OPTIONS $first_hypervisor_ip sudo vif --list | grep -B 1 $instance_ip | head -1 | awk '{print $3}' | sed 's/\r//g')
ssh $SSH_OPTIONS $first_hypervisor_ip curl -s "http://$first_hypervisor_ip:8085/Snh_ItfReq?name=$if_name"
linklocal_ip=$(ssh $SSH_OPTIONS $first_hypervisor_ip curl -s "http://$first_hypervisor_ip:8085/Snh_ItfReq?name=$if_name" | sed 's/^.*<mdata_ip_addr.*>\([0-9\.]*\)<.mdata_ip_addr>.*$/\1/')

res=1
msg="ERROR: failed to execute ssh $first_hypervisor_ip ping -c1 -w 5 $linklocal_ip"
for i in {1..5} ; do
  if ssh $SSH_OPTIONS $first_hypervisor_ip ping -c1 -w 5 $linklocal_ip ; then
    msg="INFO: suceeded ssh $first_hypervisor_ip ping -c1 -w 5 $linklocal_ip"
    res=0
    break
  fi
done
echo $msg

# Enable after metadata is working
#ssh $SSH_OPTIONS $first_hypervisor_ip sudo yum install -y sshpass || ssh $first_hypervisor_ip sudo apt-get install sshpass
#ssh $SSH_OPTIONS $first_hypervisor_ip sshpass -p 'cubswin:)'  ssh cirros@$linklocal_ip curl --connect-timeout 5 http://169.254.169.254/2009-04-04/instance-id
# Tear down
cleanup

exit $res
