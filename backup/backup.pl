#!/usr/bin/perl

# backup script
# Rootnode http://rootnode.net
#
# Copyright (C) 2011 Marcin Hlybin
# All rights reserved.

use warnings;
use strict;
use 5.010;
use DBI;
use YAML qw(LoadFile);
use FindBin qw($Bin);
use File::Path qw(rmtree);
use feature 'switch';
$|++;

# config
my $config_file = shift || "$Bin/backup.yaml";
-f $config_file or die "Config file not found!\n";
my $yaml = YAML::LoadFile($config_file);

my $rdiff     = "/bin/bash $Bin/rdiff.sh";
my $mysqldump = "/bin/bash $Bin/mysqldump.sh";
my $rdiff_opt = ""; # additional opt for rdiff

my $backup_dir   = '/backup';
my $mysql_config = '/root/.my.system.cnf';
my $mysql_tmp    = "$backup_dir/mysqltmp";

my $remove_older_than = '14D';

my $hostname = `hostname -s`;
chomp $hostname;

# interactive mode
my $debug = ! system('tty -s');
	
# db
my $dbh = DBI->connect("dbi:mysql:rootnode;mysql_read_default_file=$mysql_config",undef,undef,{ RaiseError => 1, AutoCommit => 1 });
my $db_backup_users = $dbh->prepare('SELECT login, uid FROM uids WHERE block=0 AND del=0 ORDER BY login');
my $db_remove_users = $dbh->prepare('SELECT login, uid FROM uids WHERE del=1 ORDER BY login');

$dbh->{mysql_auto_reconnect} = 1;

sub check_backup {
        my($backup_type, $server_name, $user_name) = @_;

	$user_name ||= "";

	my $last_backup = `$rdiff -l $rdiff_opt $user_name $server_name`;
	chomp $last_backup;

	if($last_backup) {
                my @current = (localtime(time))[3,4,5];
                my @backup  = (localtime($last_backup))[3,4,5];

                if(@current ~~ @backup) {
                        # we have current backup 
			$debug and print "\033[1;34mcurrent\033[0m\n";
                        return 1;
                }
        }
        return;
}

foreach my $backup_type (qw(system users mysql)) {
	$rdiff_opt = '-m' if $backup_type eq 'mysql';
	foreach my $server_name ( @{ $yaml->{$hostname}->{$backup_type} } ) {
		given($backup_type) {
			when('system') {
				my $backup_path="$backup_dir/$backup_type/$server_name";
				$debug and print $backup_path.'.'x(60-length($backup_path));

				# check for current backup
				check_backup($backup_type, $server_name) and next;

				# rdiff-backup
				system("$rdiff $server_name");
				$debug and print $? ? "\033[1;31merror\033[0m\n" : "\033[1;32mdone\033[0m\n";
				
				# remove old backups
				if(check_backup($backup_type,$server_name)) {
					system("$rdiff -r $remove_older_than $server_name");
				}
			} # system

			when('mysql') {
				# mysql system databases
				my $backup_path="$backup_dir/$backup_type/system/$server_name";
				$debug and print $backup_path.'.'x(60-length($backup_path));
				
				# check for current backup
				check_backup($backup_type, $server_name) and continue;

				system("$mysqldump $server_name");
				$debug and print "dump: ".($? ? "\033[1;31merror\033[0m " : "\033[1;32mdone\033[0m ");

				system("$rdiff -m $server_name");
				$debug and print "rdiff: ".($? ? "\033[1;31merror\033[0m\n" : "\033[1;32mdone\033[0m\n");
				
				# remove old backups
				if(check_backup($backup_type,$server_name,'')) {
					system("$rdiff -r $remove_older_than -m $server_name");
				}
				continue; # IMPORTANT!
			} # mysql

			when(/^(users|mysql)$/) {
				$db_backup_users->execute;
				while(my($user_name,$user_id) = $db_backup_users->fetchrow_array) {
					my $backup_path="$backup_dir/$backup_type/$user_name";
					$debug and print $backup_path.'.'x(60-length($backup_path));

					# check for current backup
					check_backup($backup_type, $server_name, $user_name) and next;

					if($backup_type eq 'mysql') {
						# mysqldump
						system("$mysqldump $user_id $server_name");
						$debug and print ''.($? ? "\033[1;31merror\033[0m" : "\033[1;32mdone\033[0m").' (dump) ';
					}		
	
					# rdiff-backup
					system("$rdiff $rdiff_opt $user_name $server_name");
					$debug and print $? ? "\033[1;31merror\033[0m\n" : "\033[1;32mdone\033[0m\n";
				} # while

				# remove old backups
				$db_backup_users->execute;
				while(my($user_name) = $db_backup_users->fetchrow_array) {
					if(check_backup($backup_type, $server_name, $user_name)) {
						
						given($backup_type) {
							when('users') { system("$rdiff -r $remove_older_than $user_name $server_name") }
							when('mysql') { system("$rdiff -r $remove_older_than -m $user_name $server_name") }
						}
					}
				}

				# remove old users
				$db_remove_users->execute;
				while(my($user_name) = $db_remove_users->fetchrow_array) {
					my $backup_path="$backup_dir/$backup_type/$user_name";
					   $backup_path="$backup_dir/$backup_type/users/$user_name" if $backup_type eq "mysql";
					rmtree($backup_path) if -d $backup_path;
				}
			} # users|mysql
		} # given
	} # server_name
} # backup_type

# cleanup
rmtree($mysql_tmp) if -d $mysql_tmp;
