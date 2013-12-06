#!/bin/bash
#
# Script creates some basic nets and security groups for admin user
#
# Assumes working installation of quantum
#

QUANTUM=$( which quantum || echo /bin/true )

function get_k_id 
{
   RETVAL=$( keystone ${1}-list | grep ${2} | awk '{print $2}' )
   echo $RETVAL
}

function get_q_id 
{
   RETVAL=$( $QUANTUM ${1}-list | grep ${2} | awk '{print $2}' )
   echo $RETVAL
}


#
# Get ID values
# 
PROJECT_ID=$( get_k_id tenant "admin" )
L3_AGENT_ID=$( $QUANTUM agent-list | grep "L3 agent" | awk '{print $2}' )


#------------------------------
# Setup some networks objects
# -----------------------------

# Create a private network
tenant="admin"
tenant_id=$( get_k_id tenant " ${tenant} " )

# Create a private net and subnet
net_id=$( get_q_id net "admin_private_net" )
if [ -z ${net_id} ]; then
    $QUANTUM net-create    --tenant_id $tenant_id "admin_private_net"
    net_id=$( get_q_id net "admin_private_net" )
fi


# Create a subnet or two
cidr="10.12.34.0/24"
subnet_id=$( get_q_id subnet $cidr )
if [ -z ${subnet_id} ]; then
    $QUANTUM subnet-create --tenant_id $tenant_id \
                          --ip_version 4 \
                          --name "admin_private_subnet"  \
                           "admin_private_net" "$cidr"
    subnet_id=$( get_q_id subnet "$cidr" )
fi

cidr="10.56.78.0/24"
subnet2_id=$( get_q_id subnet $cidr )
if [ -z ${subnet2_id} ]; then
    $QUANTUM subnet-create --tenant_id $tenant_id \
                          --ip_version 4 \
                          --name "admin_private_subnet2"  \
                           "admin_private_net" "$cidr"
    subnet2_id=$( get_q_id subnet "$cidr" )
fi

# Create a router & add it to the L3 agent
router_id=$(  get_q_id router "admin_router" )
if [ -z ${router_id} ]; then
    $QUANTUM router-create --tenant_id $tenant_id "admin_router"
    router_id=$(  get_q_id router "admin_router" )
fi
$QUANTUM router-interface-add "admin_router" $subnet_id || /bin/true

$QUANTUM l3-agent-router-add ${L3_AGENT_ID} admin_router

# connect it to a couple subnets

PROJECT_SUBNET_ID=$( get_q_id subnet 10.12.34.0/24 )
PROJECT_SUBNET_ID2=$( get_q_id subnet 10.56.78.0/24 )

#$QUANTUM router-interface-add admin-router ${PROJECT_SUBNET_ID}
#$QUANTUM router-interface-add admin-router ${PROJECT_SUBNET_ID2}


#------------------------------
# Setup some security groups
# -----------------------------

$QUANTUM security-group-create  admin-secgroup --description "security group for admin"
SEC_GROUP_ID=$( $QUANTUM security-group-list | grep admin-secgroup | awk '{print $2}' )

# Creating security group rule to allow web access
$QUANTUM security-group-rule-create --direction ingress \
                                   --protocol icmp \
                                   --port_range_min -1 \
                                   --port_range_max -1  \
                                   --remote-ip-prefix 0.0.0.0/0 \
                                   ${SEC_GROUP_ID}
$QUANTUM security-group-rule-create --direction ingress \
                                   --protocol tcp \
                                   --port_range_min 22  \
                                   --port_range_max 22  \
                                   --remote-ip-prefix 0.0.0.0/0 \
                                   ${SEC_GROUP_ID}

