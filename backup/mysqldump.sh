#!/bin/bash

# mysqldump script
# Rootnode http://rootnode.net
#
# Copyright (C) 2011 Marcin Hlybin
# All rights reserved.

# exit on error
set -e 

# usage
usage() {
	echo -e "Usage: $0 uid server_name [ exclude_db ]" 
	echo -e "       $0 server_name [ exclude_db ]"
	exit 1	
}

# args
[ $# -lt 1 ] && usage

# database listing
if [[ $1 =~ ^[0-9]+$ ]]
then 
	# users databases
	uid=$1
	server_name=$2
	shift 2
	db_exclude=$@
	db_exclude="${db_exclude// /\',\'}"  # add quotes
	db_list=`mysql -h $server_name.rootnode.net -Nse "
		SELECT DISTINCT table_schema FROM information_schema.tables 
		WHERE table_schema LIKE 'my{$uid}_%' 
		AND table_schema NOT IN ('information_schema',$db_exclude)"`
else
	# system databases
	server_name=$2
	shift
	db_exclude=$@
	db_exclude="${db_exclude// /\',\'}" 
	db_list=`mysql -h $server_name.rootnode.net -Nse "
		SELECT DISTINCT table_schema FROM information_schema.tables 
		WHERE table_schema NOT REGEXP '^my[0-9]{4,}_.*';
		AND table_schema NOT IN ('information_schema',$db_exclude)"`
fi

# dirs
mysql_tmp="/backup/mysqltmp"

# mysql tmp dir
[ -d $mysql_tmp ] && rm -rf -- $mysql_tmp
mkdir -p -m 700 $mysql_tmp/$server_name
cd $mysql_tmp/$server_name

# mysqldump
for database in $db_list
do
	mysqldump \
		--default-character-set=utf8 \
		--lock-tables \
		--complete-insert \
		--add-drop-table \
		--quick \
		--quote-names \
	$database > $database.sql
done
