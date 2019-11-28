#!/bin/bash
set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/openrc"

TEST_SUBNET_CIDR="${TEST_SUBNET_CIDR:-172.23.0.0/24}"
TEST_IMAGE_NAME="${TEST_IMAGE_NAME:-Cirros 0.3.5 64-bit}"
	
TEST_INSTANCE_NAME=tf-devstack-testvm
function cleanup() {
  openstack server delete tf-devstack-testvm --wait || :
  openstack flavor delete m1.micro || :
  openstack security group delete allow_ssh || :
  openstack subnet delete tf-devstack-subnet-test || :
  openstack network delete tf-devstack-test || :
}

# Clean up proactively in case previous attempt failed
cleanup

# Set up
openstack network create tf-devstack-test
openstack subnet create --subnet-range "$TEST_SUBNET_CIDR" --network tf-devstack-test tf-devstack-subnet-test
openstack security group create allow_ssh
openstack security group rule create --dst-port 22 --protocol tcp allow_ssh
openstack flavor create --ram 64 --disk 1 --vcpus 1 m1.micro

# Deploy
first_hypervisor=$(openstack hypervisor list -f value | grep up)
first_hypervisor_name=$(echo $first_hypervisor | cut -d' ' -f2)
first_hypervisor_ip=$(echo $first_hypervisor | cut -d' ' -f4)
openstack server create --availability-zone "nova::$first_hypervisor_name" --image "$TEST_IMAGE_NAME" --flavor m1.micro --nic net-id=tf-devstack-test --security-group allow_ssh --wait "$TEST_INSTANCE_NAME"

# Ensure connectivity

instance_ip=$(openstack server show $TEST_INSTANCE_NAME | awk '/addresses/{print $4}' | cut -d '=' -f 2 | sed 's/,$//g')
	
# on the hypervisor where instance run
if_name=$(ssh $first_hypervisor_ip sudo vif --list | grep -B 1 $instance_ip | head -1 | awk '{print $3}' | sed 's/\r//g')
ssh $first_hypervisor_ip curl -s "http://$first_hypervisor_ip:8085/Snh_ItfReq?name=$if_name"
linklocal_ip=$(ssh $first_hypervisor_ip curl -s "http://$first_hypervisor_ip:8085/Snh_ItfReq?name=$if_name" | sed 's/^.*<mdata_ip_addr.*>\([0-9\.]*\)<.mdata_ip_addr>.*$/\1/')
ssh $first_hypervisor_ip ping -c1 -w 5 $linklocal_ip
# Enable after metadata is working
#ssh $first_hypervisor_ip sudo yum install -y sshpass || ssh $first_hypervisor_ip sudo apt-get install sshpass
#ssh $first_hypervisor_ip sshpass -p 'cubswin:)'  ssh cirros@$linklocal_ip curl --connect-timeout 5 http://169.254.169.254/2009-04-04/instance-id
# Tear down
cleanup
