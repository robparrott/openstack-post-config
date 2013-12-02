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

IMAGES="http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img \
        http://storage.core-os.net/coreos/amd64-generic/dev-channel/coreos_production_openstack_image.img.bz2 \
        http://cloud-images.ubuntu.com/raring/20131008/raring-server-cloudimg-amd64-disk1.img \
        http://download.fedoraproject.org/pub/fedora/linux/releases/19/Images/x86_64/Fedora-x86_64-19-20130627-sda.qcow2 \
        http://knoppix.hostingxtreme.com/KNOPPIX_V7.2.0CD-2013-06-16-EN.iso \
        http://softlayer-dal.dl.sourceforge.net/project/nst/NST/NST%2018-4509/nst-18-4509.i686.iso "

    
for IMAGE in ${IMAGES}; do 
	./bin/upload-image.sh ${IMAGE}
done
