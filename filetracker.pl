#!/usr/bin/perl
#
# FileTracker.pl 1.0 (C) Smidsrød Consulting 15. June 2004->
# Written by: Robin Smidsrød <robin@smidsrod.no>
#
# Program to keep track of changes to files in a directory
# Should be run regularly (once a day/week) from cron/scheduler.
#
# This program is NOT public domain.
#

use strict;

use DBI;
use Data::Dumper;
use Data::UUID;
use Digest::MD5;
use File::Find;
use Fcntl qw(:mode);
use POSIX;

# Set to 1(true) to enable debug
our $debug=0;

our $version='1.0';

# Init database handler
my $dsn="dbi:Pg:dbname=filetracker";
our $dbh=DBI->connect($dsn); # Add username and password after DSN if DB-environment needs it.
$dbh->{'RaiseError'}=1;

# Init UUID generator
our $ug=new Data::UUID;

# Setup SQL statements
our %SQL=(
	InsertSnapshot 			=> "INSERT INTO snapshot (snapshot_id,start_time) VALUES (?,?)",
	UpdateSnapshotByID		=> "UPDATE snapshot SET end_time=? WHERE snapshot_id=?",
	InsertRoot 			=> "INSERT INTO root (root_id,path) VALUES (?,?)",
	SelectRootByPath		=> "SELECT root_id FROM root WHERE path=?",
	SelectRoots         => "SELECT root_id,path FROM root ORDER BY path",
	InsertFile			=> "INSERT INTO file (file_id,path,size,ctime,mtime,md5,root_id,snapshot_id) VALUES (?,?,?,?,?,?,?,?)",
	UpdateFileByID			=> "UPDATE file SET size=?,ctime=?,mtime=?,md5=?,snapshot_id=? WHERE file_id=?",
	SelectFileByPathAndRootID	=> "SELECT * FROM file WHERE path=? AND root_id=?",
	SelectFileByRootID		=> "SELECT file_id,path FROM file WHERE root_id=? ORDER BY path",
	DeleteFileByID			=> "DELETE FROM file WHERE file_id=?",
);

unless($ARGV[0]) {
	print STDERR "Usage: $0 <root-dir>\n";
	exit; # FAIL
}

print "FileTracker $version\n\n";

# Get root dir (1st argument)
our $rootdir=$ARGV[0];
$rootdir=~s/^(.*)\/$/$1/; # Trim trailing slash
our $root_id;
our $snapshot_id;
our $file_insert_sth;
our $file_select_sth;
our $file_update_sth;

eval {
	# Start transaction
	$dbh->begin_work;

	if ($rootdir=~/^update$/i) {

	    print "Update of all roots requested.\n";
	    
	    # Iterate through all roots
	    my $root_sth=$dbh->prepare($SQL{'SelectRoots'});
	    $root_sth->execute();
	    while( my $root=$root_sth->fetchrow_hashref() ) {
	        $rootdir=$root->{'path'};
	        $root_id=$root->{'root_id'};
	
            print "Scanning directory: $rootdir\n";

            # Prune stale files if running with existing root
            if (defined($root_id)) {

                # Prune old files which is unavailable from database if root exist
                my $prune_sth=$dbh->prepare($SQL{'DeleteFileByID'});
                my $list_sth=$dbh->prepare($SQL{'SelectFileByRootID'});
                $list_sth->execute($root_id);
                
                # Read file records and check if available
                while((my $file_id,my $filepath)=$list_sth->fetchrow_array) {
                    my $pathname=$rootdir . $filepath;
                    unless(-r $pathname) {
                        my $rc=$prune_sth->execute($file_id);
                        if($rc) {
                            print "DEL: $filepath\n";
                        } else {
                            print "ERRDEL: $filepath\n";
                        }
                    }
                }

            }

            # Insert new snapshot
            $snapshot_id=$ug->create_str;
            my $sth=$dbh->prepare($SQL{'InsertSnapshot'});
            $sth->execute($snapshot_id,strftime('%F %T',localtime(time)));
            
            # Prepare file insert statement
            $file_insert_sth=$dbh->prepare($SQL{'InsertFile'});
            $file_select_sth=$dbh->prepare($SQL{'SelectFileByPathAndRootID'});
            $file_update_sth=$dbh->prepare($SQL{'UpdateFileByID'});

            # Find files and add to database
            find(\&verify_file,$rootdir);

            # Set snapshot end-time
            my $sth=$dbh->prepare($SQL{'UpdateSnapshotByID'});
            $sth->execute(strftime('%F %T',localtime(time)),$snapshot_id);
        }
    }
    else {
        # Create new root
        $root_id=$ug->create_str;
        my $sth=$dbh->prepare($SQL{'InsertRoot'});
        $sth->execute($root_id,$rootdir);
        
        print "New root created: $rootdir ($root_id)\nPlease rerun with 'update' to scan.\n" if $sth->rows == 1;
    }

	# Commit transaction
	$dbh->commit;

};

if ($@) {
	print "Database Error, session terminated!\n", $@, "\n";
	$dbh->rollback;
	exit; # FAIL
}

exit; # OK

sub verify_file {
	my $filename=$_;

	my $pathname=$File::Find::name;
	
	# Remove root dir from pathname
	$pathname=~s/^$rootdir(.*)$/$1/;

	# Check that file is a regular file
	unless (-f $filename) {
		print "SKIPPED - Not a regular file: $pathname\n" if $debug;
		return 'dir'; # BREAK
	}

	# Check that file is readable
	unless (-r $filename) {
		print "SKIPPED - Unreadable: $pathname\n" if $debug;
		return 'unreadable'; # BREAK
	}

	# Get common file information
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($filename);

	# Check if file exist in database
	$file_select_sth->execute($pathname,$root_id);
	my $file_data=$file_select_sth->fetchrow_hashref;
	unless($file_data) {

		# Create new file entry if it doesn't exist already

		my $file_id=$ug->create_str;

		# Generate MD5 Digest for file
		open(FILE,$filename) or die "Can't open file $filename: $!\n";
		binmode(FILE);
		my $md5=Digest::MD5->new->addfile(*FILE)->hexdigest;
		close(FILE);

		my $rc=$file_insert_sth->execute($file_id,$pathname,$size,strftime('%F %T',localtime($ctime)),strftime('%F %T',localtime($mtime)),$md5,$root_id,$snapshot_id);
		if ($rc) {
			print "ADD: $pathname\n";
		} else {
			print "ERRADD: $pathname\n";
		}

	} else {
		# Verify existing database record

		# Check if mtime has changed, update if necessary
		if ($file_data->{'mtime'} eq strftime('%F %T',localtime($mtime))) {

			# File isn't changed. Leave alone
			print "UCH: $pathname\n" if $debug;

		} else {
			# MTIME has changed, check if MD5 is changed before update database

			# Generate MD5 Digest for file
			open(FILE,$filename) or die "Can't open file $filename: $!\n";
			binmode(FILE);
			my $md5=Digest::MD5->new->addfile(*FILE)->hexdigest;
			close(FILE);

			# Check if MD5 has changed
			if ($file_data->{'md5'} ne $md5) {
				# MD5 has changed, update database				
				my $file_id=$file_data->{'file_id'};

				my $rc=$file_update_sth->execute($size,strftime('%F %T',localtime($ctime)),strftime('%F %T',localtime($mtime)),$md5,$snapshot_id,$file_id);
				if ($rc) {
					print "UPD: $pathname\n";
				} else  {
					print "ERR: $pathname\n";
				}
			} else {
				# MD5 hasn't changed, someone just resaved the same file
				print "CTM: $pathname\n" if $debug;
			}

		}

	}

	return; # OK
}
