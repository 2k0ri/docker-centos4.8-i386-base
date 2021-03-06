#!/bin/bash

set -e -u -x

## execute in a Docker container to build the tarball
##   docker run --privileged -i -t -v $PWD:/srv centos:centos6 /srv/build.sh

DEST_IMG="/srv/centos48.tar.xz"

rm -f ${DEST_IMG}

yum install -y xz

instroot=$(mktemp -d)
tmpyum=$(mktemp)

cat << EOF >  ${tmpyum}
[main]
debuglevel=2
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=5
distroverpkg=centos-release

[c4-base]
name=CentOS-4 - Base
baseurl=http://vault.centos.org/4.8/os/i386/
gpgcheck=1
gpgkey=http://vault.centos.org/RPM-GPG-KEY-CentOS-4

[c4-updates]
name=CentOS-4 - Updates
baseurl=http://vault.centos.org/4.8/updates/i386/
gpgcheck=1
gpgkey=http://vault.centos.org/RPM-GPG-KEY-CentOS-4
EOF

## touch, chmod; /dev/null; /etc/fstab; 
mkdir ${instroot}/{dev,etc,proc}
mknod ${instroot}/dev/null c 1 3 
touch ${instroot}/etc/fstab

yum \
    -c ${tmpyum} \
    --disablerepo='*' \
    --enablerepo='c4-*' \
    --setopt=cachedir=${instroot}/var/cache/yum \
    --setopt=logfile=${instroot}/var/log/yum.log \
    --setopt=keepcache=1 \
    --setopt=diskspacecheck=0 \
    -y \
    --installroot=${instroot} \
    install \
    centos-release yum iputils coreutils which curl

cp /etc/resolv.conf ${instroot}/etc/resolv.conf

## yum/rpm on centos6 creates databases that can't be read by centos4's yum
## http://lists.centos.org/pipermail/centos/2012-December/130752.html
rm ${instroot}/var/lib/rpm/*
chroot ${instroot} /bin/rpm --initdb
chroot ${instroot} /bin/rpm -ivh --justdb '/var/cache/yum/*/packages/*.rpm'

chroot ${instroot} sh -c 'echo "NETWORKING=yes" > /etc/sysconfig/network'

## set timezone of container to UTC
chroot ${instroot} ln -f /usr/share/zoneinfo/Etc/UTC /etc/localtime

sed -i \
    -e '/^mirrorlist/d' \
    -e 's@^#baseurl=http://mirror.centos.org/centos/$releasever/@baseurl=http://vault.centos.org/4.8/@g' \
    ${instroot}/etc/yum.repos.d/CentOS*.repo

chroot ${instroot} yum clean all

## clean up mounts ($instroot/proc mounted by yum, apparently)
umount ${instroot}/proc
rm -f ${instroot}/etc/resolv.conf

## xz gives the smallest size by far, compared to bzip2 and gzip, by like 50%!
chroot ${instroot} tar -cf - . | xz > ${DEST_IMG}
