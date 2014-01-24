#!/bin/bash

#
# Load any functions
#
for i in $( ls include/ ); do
  source include/${i}
done


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
# Create a mini flavor for testing
#
if [[ -z $( nova flavor-list | grep m1.mini ) ]]; then
    nova flavor-create m1.mini 6 1024 5 1
fi

if [[ -z $( nova flavor-list | grep m1.nano ) ]]; then
    nova flavor-create m1.nano  7 128 0 1
fi

#
# Figure out admin's tenant ID
#
tenant="admin"
tenant_id=$( get_k_id tenant " ${tenant} " )

#
# Up admin's quotas
#
nova    quota-update --instances 100 ${tenant_id}
nova    quota-update --cores     100 ${tenant_id}
nova    quota-update --ram    102400 ${tenant_id}
neutron quota-update --port     200  > /dev/null

#
# Make sure we have an image to use 
#
 
if ! [ -r /tmp/cirros-0.3.1-x86_64-disk.img ]; then 
	wget http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img 
fi

CIRROS_IMAGE_ID=$( glance index | grep " cirros-0.3.1 " | awk '{ print $1}' )

if [ -z ${CIRROS_IMAGE_ID} ]; then
	IMAGE_INFO=$( glance image-create --name cirros-0.3.1 --is-public True --disk-format qcow2 --container-format bare --file cirros-0.3.1-x86_64-disk.img )
    CIRROS_IMAGE_ID=$( echo "${IMAGE_INFO}" |  grep "| id" | awk '{print $4}' )
fi

#echo "IMAGE_ID: ${CIRROS_IMAGE_ID}"


#
# Make sure we have another image to use 
#
 
if ! [ -r /tmp/Fedora-x86_64-19-20130627-sda.qcow2 ]; then 
	wget http://download.fedoraproject.org/pub/fedora/linux/releases/19/Images/x86_64/Fedora-x86_64-19-20130627-sda.qcow2
fi

F19_IMAGE_ID=$( glance index | grep " Fedora19 " | awk '{ print $1}' )

if [ -z ${F19_IMAGE_ID} ]; then
	IMAGE_INFO=$( glance image-create --name Fedora19 --is-public True --disk-format qcow2 --container-format bare --file Fedora-x86_64-19-20130627-sda.qcow2 )
    F19_IMAGE_ID=$( echo "${IMAGE_INFO}" |  grep "| id" | awk '{print $4}' )
fi

#echo "IMAGE2_ID: ${F19_IMAGE_ID}"


#--------------------------
# Create Neutron objects
# -------------------------



# Create a private net and subnet
NET=admin_net1
CIDR="192.168.0.0/24"
net_id=$( get_q_id net ${NET} )
if [ -z ${net_id} ]; then
    neutron net-create  --tenant_id $tenant_id "${NET}"
    net_id=$( get_q_id net "${NET}" )
fi

subnet_id=$( get_q_id subnet "${CIDR}" )
if [ -z ${subnet_id} ]; then
    neutron subnet-create --dns-nameserver ${dns_server} --tenant_id "$tenant_id" "${NET}" "${CIDR}"
    subnet_id=$( get_q_id subnet "${CIDR}" )
fi

# create a 2nd net & subnet
NET=admin_net2
CIDR="192.168.1.0/24"
net_id2=$( get_q_id net ${NET} )
if [ -z ${net_id2} ]; then
    neutron net-create  --tenant_id $tenant_id "${NET}"
    net_id2=$( get_q_id net "${NET}" )
fi

subnet_id2=$( get_q_id subnet "${CIDR}" )
if [ -z ${subnet_id2} ]; then
    neutron subnet-create --dns-nameserver ${dns_server} --tenant_id $tenant_id "${NET}" "${CIDR}"
    subnet_id2=$( get_q_id subnet "${CIDR}" )
fi

#
# Create a router and connect to these subnets
#
ROUTER=admin_router                                                                                                                                                  
router_id=$(  get_q_id router "${ROUTER}" )
if [ -z ${router_id} ]; then
    neutron router-create --tenant_id $tenant_id "${ROUTER}"
    router_id=$( get_q_id router "${ROUTER}" )
fi
neutron router-interface-add "${ROUTER}" ${subnet_id}  || /bin/true
neutron router-interface-add "${ROUTER}" ${subnet_id2} || /bin/true

#
# Create an external network matching the floating IP network space, 
#  and configure the external network as router gw 
#
PUBNET=public
CIDR="${pub_cidr}" 

pub_net_id=$( get_q_id net "${PUBNET}" )
if [ -z ${pub_net_id} ]; then                                                                                                          
    neutron net-create "${PUBNET}" --tenant_id $tenant_id --shared --router:external=True
    pub_net_id=$( get_q_id net "${PUBNET}" )
fi

pub_subnet_id=$( get_q_id subnet "${CIDR}" )
if [ -z ${pub_subnet_id} ]; then
    neutron subnet-create ${PUBNET} ${CIDR} \
                            --tenant_id $tenant_id \
                            --disable-dhcp \
                            --name public \
                            --allocation-pool=start=${floating_ip_start},end=${floating_ip_end} \
                            --dns-nameserver ${dns_server}  \
                            --gateway ${pub_gateway} || /bin/true
    pub_subnet_id=$( get_q_id subnet ${CIDR} )
fi
neutron router-gateway-set "${ROUTER}" ${pub_net_id} || /bin/true

#
# Modify the default security group to allow outbound access
#
# These may already be created, but try anyway... no harm done.
#

SECGROUP_ID=$( get_q_id security-group default ) # neutron security-group-list | grep " default " | tail -1 | awk '{print $2 }' )
if [ -z ${SECGROUP_ID} ]; then
   neutron security-group-create default --description "default"
   SECGROUP_ID=$( get_q_id security-group default ) 
fi
neutron security-group-rule-create --direction ingress --protocol tcp --port_range_min 22 --port_range_max 22    ${SECGROUP_ID}
neutron security-group-rule-create --direction ingress --protocol icmp  ${SECGROUP_ID}
neutron security-group-rule-create --direction egress  --protocol tcp --port_range_min 1  --port_range_max 65535 ${SECGROUP_ID}
neutron security-group-rule-create --direction egress  --protocol udp --port_range_min 1  --port_range_max 65535 ${SECGROUP_ID}
neutron security-group-rule-create --direction egress --protocol icmp  ${SECGROUP_ID}

#
# Create another admin security group
# 
SECGROUP_ID=$( get_q_id security-group admin-secgroup  ) 
if [ -z ${SECGROUP_ID} ]; then
   neutron security-group-create admin-secgroup --description "admin-secgroup"
   SECGROUP_ID=$( get_q_id security-group admin-secgroup  ) 
fi

# Creating security group rule to allow web access and pinging

neutron security-group-rule-create --direction ingress --protocol icmp \
                                   --remote-ip-prefix 0.0.0.0/0  ${SECGROUP_ID} > /dev/null
ports="22 80 443"
for p in ${ports}; do                                   
  neutron security-group-rule-create --direction ingress  --protocol tcp \
                                   --port_range_min ${p}  --port_range_max ${p}   \
                                   --remote-ip-prefix 0.0.0.0/0 ${SECGROUP_ID} > /dev/null
done



