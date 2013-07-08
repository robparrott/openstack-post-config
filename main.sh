#!/bin/bash -ex

source /root/keystonerc_admin || source /root/openrc

if [ -r /root/answers.txt ]; then
  tmpf=$( mktemp )
  grep "=" /root/answers.txt > ${tmpf} 
  source ${tmpf}
  rm -f ${tmpf}
fi

source ./bin/setup-admin-resources.sh
source ./bin/test-setup.sh

IMAGES="http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-uec.tar.gz \
        http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img \
        http://smoser.brickies.net/ubuntu/ttylinux-uec/ttylinux-uec-amd64-11.2_2.6.35-15_1.tar.gz \
        http://cloud-images.ubuntu.com/quantal/current/quantal-server-cloudimg-amd64-disk1.img \
        http://mattdm.fedorapeople.org/cloud-images/Fedora18-Cloud-x86_64-latest.qcow2"
    
for IMAGE in ${IMAGES}; do 
	./bin/upload-image.sh ${IMAGE}
done
