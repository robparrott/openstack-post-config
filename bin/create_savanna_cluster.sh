#!/bin/bash

#
# Load any functions
#
for i in $( ls include/ ); do
  source include/${i}
done

. localrc

cd /tmp

export SAVANNA_URL="http://localhost:8386/v1.0"

export IMAGE_NAME=savanna-0.3-vanilla-1.2.1-ubuntu-13.04
export IMAGE_URL=http://savanna-files.mirantis.com/savanna-0.3-vanilla-1.2.1-ubuntu-13.04.qcow2
export IMAGE_LOGIN_USER=ubuntu

#export IMAGE_NAME=savanna-0.3-vanilla-1.2.1-fedora-19
#export IMAGE_URL=http://savanna-files.mirantis.com/savanna-0.3-vanilla-1.2.1-fedora-19.qcow2 
#export IMAGE_LOGIN_USER=root

#
# Get an auth token, and tenant ID
#
AUTH_TOKEN=$( keystone token-get | grep " id "  | awk '{print $4}' )
OS_TENANT_ID=$( keystone token-get | grep " tenant_id "  | awk '{print $4}' )

#
# Set the 
#
#
# Install a python REST client
#
easy_install httpie 

#
# upload an image for glance
#
./bin/upload-image.sh ${IMAGE_URL}

#
# Determine ID of savanna image
#
IMAGE_ID=$( get_image ${IMAGE_NAME} )

#
# Determine ID of public floating IP pool
IP_POOL_ID=$( neutron net-list -c id -c name | sed 's/|//g' | grep ${FLOATING_IP_NET_NAME:-public} | awk '{print $1}' )


#
# register image with savanna
#
http POST ${SAVANNA_URL}/${OS_TENANT_ID}/images/${IMAGE_ID} X-Auth-Token:${AUTH_TOKEN} username=${IMAGE_LOGIN_USER}

#
# Write node templates
#
http POST ${SAVANNA_URL}/${OS_TENANT_ID}/node-group-templates X-Auth-Token:$AUTH_TOKEN <<EOF
{
    "name": "test-master-tmpl",
    "flavor_id": "3",
    "floating_ip_pool": "${IP_POOL_ID}",
    "plugin_name": "vanilla",
    "hadoop_version": "1.2.1",
    "node_processes": ["jobtracker", "namenode"]
}
EOF


http POST ${SAVANNA_URL}/${OS_TENANT_ID}/node-group-templates X-Auth-Token:$AUTH_TOKEN <<EOF
{
    "name": "test-worker-tmpl",
    "flavor_id": "3",
    "floating_ip_pool": "${IP_POOL_ID}",
    "plugin_name": "vanilla",
    "hadoop_version": "1.2.1",
    "node_processes": ["tasktracker", "datanode"]
}
EOF

#
# Determine their IDs with some crazy python ninja stuff
#
MASTER_TMPL_ID=$( http ${SAVANNA_URL}/${OS_TENANT_ID}/node-group-templates X-Auth-Token:$AUTH_TOKEN | \
	              python -c "import json,sys; j=json.loads(sys.stdin.readlines()[0]); print j['node_group_templates'][0]['id']" )

WORKER_TMPL_ID=$( http ${SAVANNA_URL}/${OS_TENANT_ID}/node-group-templates X-Auth-Token:$AUTH_TOKEN | \
	              python -c "import json,sys; j=json.loads(sys.stdin.readlines()[0]); print j['node_group_templates'][1]['id']" )


#
# Create cluster templates
#
http POST ${SAVANNA_URL}/${OS_TENANT_ID}/cluster-templates X-Auth-Token:$AUTH_TOKEN  <<EOF
{
    "name": "demo-cluster-template",
    "plugin_name": "vanilla",
    "hadoop_version": "1.2.1",
    "node_groups": [
        {
            "name": "master",
            "node_group_template_id": "${MASTER_TMPL_ID}",
            "count": 1
        },
        {
            "name": "workers",
            "node_group_template_id": "${WORKER_TMPL_ID}",
            "count": 2
        }
    ]
}
EOF



