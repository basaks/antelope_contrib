
#
#   Copyright (c) 2009-2010 Lindquist Consulting, Inc.
#   All rights reserved. 
#                                                                     
#   Written by Dr. Kent Lindquist, Lindquist Consulting, Inc. 
#
#   This software is licensed under the New BSD license: 
#
#   Redistribution and use in source and binary forms,
#   with or without modification, are permitted provided
#   that the following conditions are met:
#   
#   * Redistributions of source code must retain the above
#   copyright notice, this list of conditions and the
#   following disclaimer.
#   
#   * Redistributions in binary form must reproduce the
#   above copyright notice, this list of conditions and
#   the following disclaimer in the documentation and/or
#   other materials provided with the distribution.
#   
#   * Neither the name of Lindquist Consulting, Inc. nor
#   the names of its contributors may be used to endorse
#   or promote products derived from this software without
#   specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
#   CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
#   WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
#   PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
#   THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY
#   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
#   USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
#   IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
#   USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#   POSSIBILITY OF SUCH DAMAGE.
#

require "getopts.pl";

use strict;

use DBI;
use Datascope;
use Datascope::db2sql;
use Datascope::dbmon;

our( $opt_1, $opt_l, $opt_n, $opt_p, $opt_r, $opt_v, $opt_V );

our( $Datascope_dbname, $Sql_dbname, $Syncstring );
our( $refresh_interval_sec, $schema_create_errors_nonfatal, $enable_mysql_auto_reconnect, @table_subset );
our( $dbh, $hookname );

sub inform {
	my( $msg ) = @_;

	if( $opt_v || $opt_V ) {

		elog_notify( $msg );
	}
}

sub Inform {
	my( $msg ) = @_;

	if( $opt_V ) {

		elog_notify( $msg );
	}
}

sub sqldb_is_present {
	my( $dbh, $sqldbname ) = @_;

	my @dbnames = map { @$_ } @{$dbh->selectall_arrayref( "SHOW DATABASES" )};

	if( grep( /^$sqldbname$/, @dbnames ) ) {
		
		return 1;

	} else {

		return 0;
	}

}

sub init_sql_database {
	my( $dbh, $sqldbname, $rebuild ) = splice( @_, 0, 3 );
	my( @db ) = splice( @_, 0, 4 );
	my( $hookname ) = pop( @_ );

	if( sqldb_is_present( $dbh, $sqldbname ) ) {

		if( $rebuild ) {

			inform( "Database '$sqldbname' already exists. Dropping '$sqldbname'\n" );

			my( $cmd ) = "DROP DATABASE $sqldbname;";

			Inform( "Executing SQL Command:\n$cmd\n\n" );

			unless( $dbh->do( $cmd ) ) {

				elog_die( "Failed to drop pre-existing database '$sqldbname'. Bye.\n" );
			}

			# Fall through to re-create database

		} else {

			my( $cmd ) = "USE $sqldbname;";

			Inform( "Executing SQL Command:\n$cmd\n\n" );

			unless( $dbh->do( $cmd ) ) {

				elog_die( "Failed to switch to database '$sqldbname'. Bye.\n" );
			}

			inform( "Resynchronizing SQL database '$sqldbname' with Datascope database '$Datascope_dbname'\n" );

			dbmon_resync( $hookname, $dbh );

			return;
		}
	}

	my( $cmd ) = "CREATE DATABASE $sqldbname;";

	Inform( "Executing SQL Command:\n$cmd\n\n" );

	unless( $dbh->do( $cmd ) ) {

		elog_die( "Failed to create database '$sqldbname'. Bye.\n" );
	}

	$cmd = "USE $sqldbname;";

	Inform( "Executing SQL Command:\n$cmd\n\n" );

	unless( $dbh->do( $cmd ) ) {

		elog_die( "Failed to switch to database '$sqldbname'. Bye.\n" );
	}

	foreach $cmd ( sql_create_commands( @db, @table_subset ) ) {

		Inform( "Executing SQL Command:\n$cmd\n\n" );

		unless( $dbh->do( $cmd ) ) {

			if( $schema_create_errors_nonfatal ) {

				elog_complain( "Table creation failed for '$sqldbname' using command\n\n$cmd\n\nContinuing.\n\n" );

			} else {

				elog_die( "Table creation failed for '$sqldbname' using command\n\n$cmd\n\nBye.\n\n" );
			}
		}
	}

	return;
}

sub sql_create_commands {
	my( @db ) = splice( @_, 0, 4 );
	my( @table_subset ) = @_;

	my( @cmds, $table );

	if( @table_subset > 0 ) {

		while( $table = shift( @table_subset ) ) {
			
			@db = dblookup( @db, "", $table, "", "" );

			push( @cmds, dbschema2sqlcreate( @db ) );
		}

	} else {

		@cmds = dbschema2sqlcreate( @db );
	}
	
	return @cmds;
}

sub sql_insert_commands {
	my( @db ) = splice( @_, 0, 4 );
	my( @table_subset ) = @_;

	my( @cmds, $table );

	if( @table_subset > 0 ) {

		while( $table = shift( @table_subset ) ) {
			
			@db = dblookup( @db, "", $table, "", "" );

			push( @cmds, db2sqlinsert( @db, \&dbmon_compute_row_sync ) );
		}

	} else {

		@cmds = db2sqlinsert( @db, \&dbmon_compute_row_sync );
	}
	
	return @cmds;
}

sub newrow {
	my( @db ) = splice( @_, 0, 4 );
	my( $table, $irecord, $sync, $dbh ) = @_;

	my( $cmd ) = db2sqlinsert( @db, \&dbmon_compute_row_sync );

	Inform( "Executing SQL Command:\n$cmd\n\n" );

	unless( $dbh->do( $cmd ) ) {
		
		elog_complain( "Failed to create new database row in table '$table'\n" .
			       "record $irecord, sync '$sync'\n" .
			       "while executing command '$cmd'\n" );
	}

	return;
}

sub delrow {
	my( @db ) = splice( @_, 0, 4 );
	my( $table, $sync, $dbh ) = @_;

	my( $cmd ) = db2sqldelete( @db, $sync );

	Inform( "Executing SQL Command:\n$cmd\n\n" );

	unless( $dbh->do( $cmd ) ) {

		elog_complain( "Failed to delete database row in table '$table', sync '$sync'\n" .
			       "while executing command '$cmd'\n" );
	}

	return;
}

sub querysyncs {
	my( @db ) = splice( @_, 0, 4 );
	my( $table, $dbh ) = @_;

	my( @syncs ) = ();

	my( $query ) = "SELECT $Syncstring FROM $table;";

	Inform( "Executing SQL Query:\n$query\n\n" );

	my( $ref ) = $dbh->selectcol_arrayref( $query );

	if( defined( $ref ) ) {

		@syncs = @{$ref};
	}

	Inform( sprintf( "Resynchronizing with %d sync strings for table '$table'\n\n", scalar(@syncs) ) );

	return @syncs;
}

my( $path, $Program_name ) = parsepath( $0 );

elog_init( $Program_name, @ARGV );

our( $Pf ) = "db2sql";

our( $Rebuild ) = 0;

our( $Usage ) = "Usage: db2sql [-lrvV] [-p pfname] datascope_dbname[.table] [sql_dbname]\n";

if( ! Getopts( '1lp:rvV' ) ) { 

	elog_die( $Usage );
} 

if( $opt_l ) {

	if( @ARGV != 1 ) {

		elog_die( $Usage );

	} else {

		$Datascope_dbname = pop( @ARGV );
	}

} else {

	if( @ARGV != 2 ) {

		elog_die( $Usage );

	} else {

		$Sql_dbname = pop( @ARGV );
		$Datascope_dbname = pop( @ARGV );
	}
}

if( $opt_r ) {

	$Rebuild = 1;
}

if( $opt_p ) {

	$Pf = $opt_p;
}

our( @db ) = dbopen_database( $Datascope_dbname, "r" );

if( $db[0] < 0 ) {

	elog_die( "Failed to open database '$Datascope_dbname' for reading. Bye.\n" );
}

if( $db[1] >= 0 ) {

	push( @table_subset, dbquery( @db, dbTABLE_NAME ) );

} else {
	
	@table_subset = @{pfget( $Pf, "table_subset" )};
}

if( $opt_l ) {

	print join( "\n", sql_create_commands( @db, @table_subset ) );

	print join( "\n", sql_insert_commands( @db, @table_subset ) );

	exit( 0 );
}

inform( "Importing '$Datascope_dbname' into '$Sql_dbname' starting at " . strtime(now()) . " UTC\n" );

$Syncstring = db2sql_get_syncfield_name();

pfconfig_asknoecho();

$refresh_interval_sec = pfget( $Pf, "refresh_interval_sec" );
$schema_create_errors_nonfatal = pfget_boolean( $Pf, "schema_create_errors_nonfatal" );
$enable_mysql_auto_reconnect = pfget_boolean( $Pf, "enable_mysql_auto_reconnect" );

my( $dsn ) = pfget( $Pf, "dsn" );
my( $user ) = pfget( $Pf, "user" );

my( $pw ) = pfget( $Pf, "password" );

unless( $dbh = DBI->connect( $dsn, $user, $pw ) ) {

	elog_die( "Failed to connect to '$dsn' as user '$user'. Bye.\n" );
}

undef( $pw );

if( $enable_mysql_auto_reconnect ) {

	Inform( "Enabling 'mysql_auto_reconnect'\n" );

	$dbh->{mysql_auto_reconnect} = 1;
}

$hookname = "dbmon_hook";

dbmon_init( @db, $hookname, \&newrow, \&delrow, \&querysyncs, @table_subset );

init_sql_database( $dbh, $Sql_dbname, $Rebuild, @db, $hookname );

dbmon_update( $hookname, $dbh );

inform( "Imported first snapshot of '$Datascope_dbname' into '$Sql_dbname' at " . strtime(now()) . " UTC\n" );

while( ! $opt_1 ) {

	sleep( $refresh_interval_sec );

	dbmon_update( $hookname, $dbh );

	Inform( "Updated snapshot of '$Datascope_dbname' into '$Sql_dbname' at " . strtime(now()) . " UTC\n" );
}

$dbh->disconnect();

dbmon_close( $hookname );

inform( "Done importing '$Datascope_dbname' into '$Sql_dbname' at " . strtime(now()) . " UTC\n" );

exit( 0 );
