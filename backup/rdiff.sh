#!/bin/bash

# rdiff-backup script
# Rootnode http://rootnode.net
#
# Copyright (C) 2011 Marcin Hlybin
# All rights reserved.

# exit on error
set -e

# usage
usage() {
	echo "Usage: $0 [ -l | -r time_spec ] [ -m | user_name ] server_name"
	echo ""
	echo "OPTIONS"
	echo "   -l              list epoch of the last backup"
	echo "   -r time_spec    remove backup older than time_spec"
	echo "   -m user_name    create user mysql backup"
	echo "   -m server_name  create system mysql backup"
	echo ""
	exit 1	
}

[ $# -eq 0 ] && usage

# dirs
home_dir="/home"
backup_dir="/backup"
mysql_tmp="/backup/mysqltmp"
cd $backup_dir 

# options
while getopts ":lkr:m" opt
do
	case $opt in
	l) do_listing=1 ;;
	k) do_showkey=1 ;;
	r) do_remove=1; remove_older_than=$OPTARG ;;
	m) backup_type="mysql" ;;
	*) usage ;;
	esac
done

shift $((OPTIND-1))
	
# Bash magic!
user_name=${2+$1}                                             # user_name = $1 if defined $2
server_name=${2-$1}                                           # server_name = defined $2 ? $1 : $2
backup_type=${backup_type}${backup_type+/}${user_name:+users} # add '/' if backup_type defined, add 'users' if user_name defined
backup_type=${backup_type/%\//\/system}                       # append 'system' if backup_type ends up with '/'
backup_type=${backup_type:-system}                            # backup_type = system if not defined 

# set proper path
case $backup_type in 
	system )         backup_path="$backup_dir/$backup_type/$server_name" ;;
	users|mysql* )   backup_path="$backup_dir/$backup_type/$user_name/$server_name" ;;
esac

# listing
if [ $do_listing ] 
then
	/usr/bin/rdiff-backup --parsable-output -l $backup_path 2>/dev/null | grep directory | tail -1 | cut -d' ' -f1
	exit;
fi

# show key
if [ $do_showkey ]
then
	# client side /root/.ssh/authorized_keys files
	[ ! -f "/root/.ssh/id_rsa.pub" ] && echo "No SSH key!" && exit 1
	hostname=`hostname --fqdn`
	ssh_key=`cat /root/.ssh/id_rsa.pub`
	cat <<EOF	
command="nice -n 19 /usr/bin/rdiff-backup --server --restrict-read-only /",\
from="$hostname",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty \
$ssh_key
EOF
fi

# remove backup
if [ $do_remove ] 
then
	/usr/bin/rdiff-backup -v0 --force --remove-older-than $remove_older_than $backup_path
	exit;
fi

# set server specific options
case $server_name in
	cox )
		home_dir="/home/mail"
		rdiff_include_special="--include=/home/lists"
		;;
	venema ) 
		home_dir="/home2"
		;;
esac

# set rdiff includes
case $backup_type in 
	system ) 
		rdiff_include="
			--include=/adm \
			--include=/etc \
			--include=/root \
			--include=/usr/src \
			--include=/usr/local \
			--include=/var/spool/cron \
			--include=/var/backups"
		;;
	users ) 
		rdiff_include="--include=$home_dir/$user_name"
		rdiff_include_special=""
		;;
esac


# create backup
case $backup_type in
	system|users ) 
		[ -d $backup_path ] || mkdir -p -m 700 $backup_path
		/usr/bin/rdiff-backup \
			$rdiff_include \
			$rdiff_include_special \
			--exclude=/* \
			--exclude-device-files \
			--exclude-fifos \
			--exclude-sockets \
			--exclude-if-present .nobackup \
			--preserve-numerical-ids \
		root@$server_name.rootnode.net::/ $backup_path 2>/dev/null
		;;
	mysql* )
		[[ $(ls -A $mysql_tmp/$server_name 2>/dev/null | wc -l) -gt 0 ]] || exit 0
		[ -d $backup_path ] || mkdir -p -m 700 $backup_path
		/usr/bin/rdiff-backup $mysql_tmp/$server_name $backup_path
		rm -rf -- $mysql_tmp
		;;
esac
