#!/bin/bash

# rdiff-backup system script
# Rootnode http://rootnode.net
#
# Copyright (C) 2011 Marcin Hlybin
# All rights reserved.

set -e # exit on error
[ ! $1 ] && echo "Usage: $0 server_name" && exit 1 

dir=${rdiff_dir:-/backup/system}
server=$1 

cd $dest
[ ! -d $server ] && mkdir -m 700 $server 

/usr/bin/rdiff-backup \
	--include=/adm \
	--include=/etc \
	--include=/root \
	--include=/usr/src \
	--include=/usr/local \
	--include=/var/spool/cron \
	--include=/var/backups \
	--exclude=/* \
root@$server.rootnode.net::/ /$dir/$server

## client file /root/.ssh/authorized_keys
# command="nice-n 19 /usr/bin/rdiff-backup --server --restrict-read-only /",from="IP ADDRESS HERE",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa SSH_KEY_HERE
