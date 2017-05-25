#! /bin/bash

hostName=
ramSize=
hdSize=

virt-install \
--name $hostName \
--ram $ramSize \
--disk path='/media/data/images/$hostName.img,size=$hdSize' \
--vcpus 1 \
--os-type linux \
--os-variant ubuntu16.04 \
--network bridge=br0 \
--graphics none \
--console pty,target_type=serial \
--location 'http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/' \
--initrd-inject='/var/lib/libvirt/boot/preseed.cfg' \
--extra-args 'console=ttyS0,115200n8 serial hostname=$hostName'

