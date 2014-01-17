#!/bin/bash -ex

#
# Try to find a credentials file to source
#

source /root/keystonerc_admin || source /root/openrc || /bin/true

if [ -r /root/answers.txt ]; then
  tmpf=$( mktemp )
  grep "=" /root/answers.txt > ${tmpf} 
  source ${tmpf}
  rm -f ${tmpf}
fi

# 
# Source a localrc file
#
source localrc

#
# Load any functions
#
for i in $( ls include/ ); do
  source ${i}
done

#
# Create EC2 credentials for 
#
./bin/create_ec2_credentials.sh

#
# Load a set of useful images into glance
#
for IMAGE in ${IMAGES}; do 
  ./bin/upload-image.sh ${IMAGE}
done

#
# Create admin objects
#
./bin/create_admin_objects.sh
#source ./bin/setup-admin-resources.sh


#
# Create a testing environment for tempest
#
echo "skipping creation of testing objects for now..."
#source ./bin/create_testing_objects.sh

#
# Create a demo user setup
#
source ./bin/demo-setup.sh
