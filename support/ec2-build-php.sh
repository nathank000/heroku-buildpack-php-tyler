#!/bin/bash
# use AMI ami-04c9306d
# run this script as root on EC2 machine.

## EDIT
export S3_BUCKET="heroku-buildpack-php-tyler"
export LIBMCRYPT_VERSION="2.5.8"
export PHP_VERSION="5.4.3"
export APC_VERSION="3.1.10"
export PHPREDIS_VERSION="2.2.1"
## END EDIT

orig_dir=$( pwd )

echo "+ Using S3 update sources..."
sed -i 's/us-east-1.ec2.archive.ubuntu.com/us-east-1.ec2.archive.ubuntu.com.s3.amazonaws.com/g' /etc/apt/sources.list

echo "+ Updating apt-get sources..."
apt-get -y update

echo "+ Installing build dependencies..."
# install build deps
apt-get -y install g++ \
gcc \
libssl-dev \
libpng-dev \
libjpeg-dev \
libxml2-dev \
libmysqlclient-dev \
libpq-dev \
libpcre3-dev \
php5-dev \
php-pear \
curl \
libcurl3 \
libcurl3-dev \
php5-curl \
libsasl2-dev \
libbz2-dev \
ccache \
git-core
#libmcrypt-dev \

# update path to use ccache
export PATH=/usr/lib/ccache:$PATH

# retrieve ccache
echo "+ Fetching compiler cache..."
curl -f -L "https://s3.amazonaws.com/${S3_BUCKET}/ccache.tar.bz2" -o - | tar xj

mkdir build && pushd build

echo "+ Fetching libmcrypt libraries..."
# install mcrypt for portability.
mkdir -p /app/local
curl -L "https://s3.amazonaws.com/${S3_BUCKET}/libmcrypt-${LIBMCRYPT_VERSION}.tar.gz" -o - | tar xz -C /app/local

echo "+ Fetching PHP sources..."
#fetch php, extract
curl -L http://us.php.net/get/php-$PHP_VERSION.tar.bz2/from/www.php.net/mirror -o - | tar xj

pushd php-$PHP_VERSION

echo "+ Configuring PHP..."
# new configure command
## WARNING: libmcrypt needs to be installed.
./configure \
--prefix=/app/vendor/php \
--with-config-file-path=/app/vendor/php \
--with-config-file-scan-dir=/app/vendor/php/etc.d \
--disable-debug \
--disable-rpath \
--enable-fpm \
--enable-gd-native-ttf \
--enable-inline-optimization \
--enable-libxml \
--enable-mbregex \
--enable-mbstring \
--enable-pcntl \
--enable-soap=shared \
--enable-zip \
--with-bz2 \
--with-curl \
--with-gd \
--with-gettext \
--with-jpeg-dir \
--with-mcrypt=/app/local \
--with-iconv \
--with-mhash \
--with-mysql \
--with-mysqli \
--with-openssl \
--with-pcre-regex \
--with-pdo-mysql \
--with-png-dir \
--with-zlib \
--without-pdo-sqlite \
--without-sqlite3

echo "+ Compiling PHP..."
# build & install it
make install

popd

# update path
export PATH=/app/vendor/php/bin:$PATH

# configure pear
pear config-set php_dir /app/vendor/php

echo "+ Installing APC..."
# install apc from source
curl -L http://pecl.php.net/get/APC-${APC_VERSION}.tgz -o - | tar xz
pushd APC-${APC_VERSION}
# php apc jokers didn't update the version string in 3.1.10.
sed -i 's/PHP_APC_VERSION "3.1.9"/PHP_APC_VERSION "3.1.10"/g' php_apc.h
phpize
./configure --enable-apc --enable-apc-filehits --with-php-config=/app/vendor/php/bin/php-config
make && make install
popd

echo "+ Installing memcache..."
# install memcache
yes '' | pecl install memcache
# answer questions
# "You should add "extension=memcache.so" to php.ini"

echo "+ Installing phpredis..."
# install phpredis
git clone git://github.com/nicolasff/phpredis.git
pushd phpredis
git checkout ${PHPREDIS_VERSION}

phpize
./configure
make && make install
# add "extension=redis.so" to php.ini
popd

echo "+ Packaging PHP..."
# package PHP
echo "5.4.1" > /app/vendor/php/VERSION
pushd /app/vendor/php
tar czf $orig_dir/php-${PHP_VERSION}-with-fpm-heroku.tar.gz *
popd

echo "+ Binaries are packaged in $orig_dir/*.tar.gz. Upload to s3 bucket of your choice."

tar cjf ccache.tar.bz2 .ccache/

echo "+ Compiler cache packaged in $orig_dir/ccache.tar.bz2. Upload to s3 bucket of your choice."
echo "+ Done!"
