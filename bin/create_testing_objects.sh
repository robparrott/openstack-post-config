#!/bin/bash

#function get_k_id 
# {
#   RETVAL=$( keystone ${1}-list | grep "${2}" | awk '{print $2}' )
#   echo $RETVAL
#}

#function get_q_id 
# {
#   RETVAL=$( neutron ${1}-list | grep "${2}" | awk '{print $2}' )
#   echo $RETVAL
#}

cd /tmp

#
# Make sure we have an image to use 
#
 
if ! [ -r /tmp/cirros-0.3.1-x86_64-disk.img ]; then 
	wget http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img 
fi

CIRROS_IMAGE_ID=$( glance index | grep testing-cirros-0.3.1 | awk '{ print $1}' )

if [ -z ${CIRROS_IMAGE_ID} ]; then
	IMAGE_INFO=$( glance image-create --name testing-cirros-0.3.1 --is-public True --disk-format qcow2 --container-format bare --file cirros-0.3.1-x86_64-disk.img )
    CIRROS_IMAGE_ID=$( echo "${IMAGE_INFO}" |  grep "| id" | awk '{print $4}' )
fi

echo "IMAGE_ID: ${CIRROS_IMAGE_ID}"


#
# Make sure we have another image to use 
#
 
if ! [ -r /tmp/Fedora-x86_64-19-20130627-sda.qcow2 ]; then 
	wget http://download.fedoraproject.org/pub/fedora/linux/releases/19/Images/x86_64/Fedora-x86_64-19-20130627-sda.qcow2
fi

F19_IMAGE_ID=$( glance index | grep testing-Fedora19 | awk '{ print $1}' )

if [ -z ${F19_IMAGE_ID} ]; then
	IMAGE_INFO=$( glance image-create --name testing-Fedora19 --is-public True --disk-format qcow2 --container-format bare --file Fedora-x86_64-19-20130627-sda.qcow2 )
    F19_IMAGE_ID=$( echo "${IMAGE_INFO}" |  grep "| id" | awk '{print $4}' )
fi

echo "IMAGE2_ID: ${F19_IMAGE_ID}"

#
# TODO Create testing tenants and users
#
#
#- name: create a test tenant
#  keystone_user: token={{ admin_token.stdout }} tenant=test_tenant tenant_description="New Tenant for Testing"
#  register: tenant1
#
#- name: create a test tenant again
#  keystone_user: token={{ admin_token.stdout }} tenant=test_tenant2  tenant_description="New Tenant for Testing v2"
#  register: tenant2
#
#- name: Create the user for tenant 1
#  keystone_user: token={{ admin_token.stdout }} user=test_user tenant=test_tenant
#                                  password={{ admin_pass.stdout }}
#
#- name: Create the user for tenant 2
#  keystone_user: token={{ admin_token.stdout }} user=test_user2 tenant=test_tenant2
#                                  password={{ admin_pass.stdout }}


#
# Create Neutron objects
# 
                                                                                                                                                                                                    
id="1"

tenant="test_tenant"
tenant_id=$( get_k_id tenant " ${tenant} " )

# Create a private net and subnet
net_id=$( get_q_id net "test_private_net" )
if [ -z ${net_id} ]; then
    neutron net-create  --tenant_id $tenant_id "test_private_net"
    net_id=$( get_q_id net "test_private_net" )
fi

subnet_id=$( get_q_id subnet "192.168.10${id}.0/24" )
if [ -z ${subnet_id} ]; then
    neutron subnet-create --tenant_id $tenant_id \
                          --ip_version 4 \
                          --gateway "192.168.10${id}.1" \
                          --name "test_private_subnet"  \
                           "test_private_net" "192.168.101.0/24"
    subnet_id=$( get_q_id subnet "192.168.101.0/24" )
fi

# Create a router and interface on the router.
router_id=$(  get_q_id router "test_router" )
if [ -z ${router_id} ]; then
    neutron router-create --tenant_id $tenant_id "test_router"
    router_id=$(  get_q_id router "test_router" )
fi
neutron router-interface-add "test_router" $subnet_id || /bin/true

# Get public net and configure the external network as router gw 
pub_net_id=$( get_q_id net " public " )
if [ -n ${pub_net_id} ]; then 
    neutron router-gateway-set "test_router" $pub_net_id || /bin/true
fi



