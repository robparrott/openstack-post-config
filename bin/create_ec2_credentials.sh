#!/bin/bash

EC2_ACCESS_KEY=$( keystone ec2-credentials-list | grep admin | awk '{print $4}' )

if [ -z ${EC2_CREDS} ]; then 
  EC2_ACCESS_KEY=$( keystone ec2-credentials-create | grep access | awk '{print $4}' )
fi

EC2_SECRET_KEY=$( keystone ec2-credentials-get --access ${EC2_ACCESS_KEY} | grep secret | awk '{print $4}'  )

cat > ~/.aws.conf <<EOF
[default]
aws_access_key_id=${EC2_ACCESS_KEY}
aws_secret_access_key=${EC2_SECRET_KEY}
region=nova
EOF


