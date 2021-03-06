#!/usr/bin/env bash

#
# Load any functions
#
for i in $( ls include/ ); do
  source include/${i}
done


NOVA=$( which nova || echo /bin/true )
QUANTUM=$( which quantum || echo /bin/true )

#function get_k_id 
# {
#   RETVAL=$( keystone ${1}-list | grep ${2} | awk '{print $2}' )
#   echo $RETVAL
#}
#
#function get_q_id 
# {
#   RETVAL=$( $QUANTUM ${1}-list | grep ${2} | awk '{print $2}' )
#   echo $RETVAL
#}


# Create A Flavor
# ---------------

# Get OpenStack admin auth
#source $TOP_DIR/openrc admin admin

# Name of new flavor
# set in ``localrc`` with ``DEFAULT_INSTANCE_TYPE=m1.micro``
MI_NAME=m1.micro

# Create micro flavor if not present
if [[ -z $($NOVA flavor-list | grep $MI_NAME) ]]; then
    $NOVA flavor-create $MI_NAME 17 256 0 1 > /dev/null 2&>1
fi

#------------------------------
#
# Setup a separate set of demo
#   user objects
#
#------------------------------


# Set values from ansible

PROJECT=${DEMO_PROJECT_NAME:-demo_project}
USERNAME=${DEMO_USERNAME:-demo_user}
PASSWD=${DEMO_PASSWORD:-$OS_PASSWORD}
EMAIL=${DEMO_EMAIL:-demo@example.com}
PROJECT_NET_NAME=demo_net
PROJECT_SUBNET_NAME=demo_subnet
PROJECT_ROUTER_NAME=demo_router

# Create a project and get its ID

PROJECT_ID=$( get_k_id tenant ${PROJECT} )
if [ -z "$PROJECT_ID" ]; then
  keystone tenant-create --name ${PROJECT}
  PROJECT_ID=$( get_k_id tenant ${PROJECT} )
fi

# Create a new user and assign the member role 
#  to it in the new tenant (keystone role-list 
#   to get the appropriate id):

ROLE_ID=$( get_k_id role "Member" )
USER_ID=$( get_k_id user ${USERNAME}  )
if [ -z "$USER_ID" ]; then
  keystone user-create --name=${USERNAME} --pass=${PASSWD} --tenant-id ${PROJECT_ID} --email=${EMAIL}
  USER_ID=$( get_k_id user ${USERNAME}  )
  keystone user-role-add --tenant-id ${PROJECT_ID} --user-id ${USER_ID} --role-id ${ROLE_ID}
fi

#------------------------------
#
# Create networks for the demo user
#
#------------------------------

# Create a new network for the tenant:

PROJECT_NET_ID=$( get_q_id net ${PROJECT_NET_NAME} )
if [ -z "$PROJECT_NET_ID" ]; then
  $QUANTUM net-create --tenant-id ${PROJECT_ID} ${PROJECT_NET_NAME}
  PROJECT_NET_ID=$( get_q_id net ${PROJECT_NET_NAME} )
fi
  
# Create a new subnet inside the new tenant network:

CIDR="50.50.1.0/24"
PROJECT_SUBNET_ID=$( get_q_id subnet $CIDR )
if [ -z "$PROJECT_SUBNET_ID" ]; then
  $QUANTUM subnet-create --tenant-id ${PROJECT_ID} \
                        --name ${PROJECT_SUBNET_NAME} \
                        ${PROJECT_NET_NAME} \
                        $CIDR
  PROJECT_SUBNET_ID=$( get_q_id subnet $CIDR )
fi  
  
# Create a router for the new tenant:

PROJECT_ROUTER_ID=$( get_q_id router ${PROJECT_ROUTER_NAME} )
if [ -z "$PROJECT_ROUTER_ID" ]; then
  $QUANTUM router-create --tenant-id  ${PROJECT_ID} ${PROJECT_ROUTER_NAME}
  PROJECT_ROUTER_ID=$( get_q_id router ${PROJECT_ROUTER_NAME} )
fi

# Add the router to the running l3 agent:

L3_AGENT_ID=$( $QUANTUM agent-list | grep "L3 agent" | awk '{print $2}' )
$QUANTUM l3-agent-router-add ${L3_AGENT_ID}  ${PROJECT_ROUTER_NAME} > /dev/null 2&>1 

# Add the router to the subnet:
$QUANTUM router-interface-add ${PROJECT_ROUTER_ID} ${PROJECT_SUBNET_ID}



#------------------------------
# Setup some security groups
# -----------------------------
SECGROUP_ID=$( get_q_id security-group demo-webservers  ) 
if [ -z ${SECGROUP_ID} ]; then
   neutron security-group-create --tenant-id ${PROJECT_ID} demo-secgroup --description "demo-webservers"
   SECGROUP_ID=$( get_q_id security-group demo-webservers  ) 
fi

# Creating security group rule to allow web access
neutron security-group-rule-create --tenant-id ${PROJECT_ID} --direction ingress --protocol icmp \
                                      --remote-ip-prefix 0.0.0.0/0 ${SECGROUP_ID}
ports="22 80 443"
for p in ${ports}; do                                   
  neutron security-group-rule-create --tenant-id ${PROJECT_ID} --direction ingress  --protocol tcp \
                                   --port_range_min ${p}  --port_range_max ${p}   \
                                   --remote-ip-prefix 0.0.0.0/0 ${SECGROUP_ID} > /dev/null
done
