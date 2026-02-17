#!/bin/sh

# ------------------------------------------------------------
# ssh Server
# ------------------------------------------------------------

apk update
apk add openssh git
rc-service sshd start
git clone https://github.com/mc-b/lerncloud
mkdir .ssh
cp lerncloud/ssh/lerncloud.pub .ssh/authorized_keys
chmod 600 .ssh/authorized_keys