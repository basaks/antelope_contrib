
#
#output is log format standard: IMS1.0:short
#
#

# future development plans: more flexible
# subsetting should be allowed;

#
# originally J.Eakins 6/1999
# mods by C.Geddes 12/1999
# re-written after format change
#  J.Eakins 2/2007 - 4/2007
# mods for file naming 
#  J.Eakins 1/2008 
# add back in an indicator for prefor
#  J.Eakins 4/2008
# 
# finally program magnitudes
#  J.Eakins 5/2009

use Getopt::Std ;
use Datascope;
use utilfunct ;
use File::Path;
use feature "switch";

use strict 'vars' ;
# debug
#use diagnostics;

our ( $opt_d, $opt_f, $opt_t, $opt_s, $opt_e, $opt_l, $opt_p, $opt_m, $opt_v, $opt_V, $opt_y);
our ( $host, $pgm, $usage) ;
our ( %pf ) ;

{    #  Main program
    my ( $Pf, $amp, $arid, $arrtime, $arrtime_ms, $arrtimesb, $artime, $assoc, $atime, $auth, $azim, $azres, $blank, $chan, $cmd, $database, $delta, $deltime, $dist, $evaz, $event, $evid, $filename, $filtype, $fm, $hashname, $hour, $isdst, $loc, $mag_auth, $magerr, $maginfo, $maglist, $magtype, $mday, $min, $minmaxind, $mon, $net, $netmag, $netmagtype, $nevents, $nsta, $orauth, $orid, $origin, $per, $phase, $pickinfo, $pre, $prefor, $refj, $refnetmag, $refstamag, $sec, $slodef, $slow, $snr, $sres, $sta, $stamag, $stime, $t, $tasdef, $time_subset, $tres, $value, $wday, $yday, $year ) ;
    my ( @db, @dbevent_b, @dbevent_g, @dbj, @dbnetmag, @dborigin_b, @dborigin_g, @dbstamag ) ;
    $pgm = $0 ; 
    $pgm =~ s".*/"" ;
    elog_init($pgm, @ARGV);
    $cmd = "\n$0 @ARGV" ;
    
    if (  ! &getopts('nvVye:f:l:m:p:s:t:') || ( @ARGV != 1 && @ARGV != 10 ) ) { 
        $usage  =  "\n\n\nUsage: $0  [-v] [-V] [-y] [-m] " ;
        $usage .=  "[-s start_origin.time] [-e end_origin.time] [-p pf] [-l logfile] [-d dbops] database  \n\n" ;
        elog_notify($cmd) ; 
        elog_die ( $usage ) ; 
    }
    
    $opt_v      = defined($opt_V) ? $opt_V : $opt_v ;
    chop ($host = `uname -n` ) ;
    
    $Pf = $opt_p || $pgm ;
    %pf = getparam( $Pf );

    $database	=  $ARGV[0];

    announce( 0, 0 )  ;
    
    elog_notify( $cmd ) ; 
    
    $stime = strydtime( now() );
    elog_notify ( "\nstarting execution on	$host	$stime\n\n" );
    elog_notify( "\ndatabase is: $database\n" ) if $opt_v ;

    prettyprint( \%pf ) if $opt_V ;
        
    $t = time() ;
    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($t) ; 

# get variables set up with getopts
    
    if ( $opt_s ) {
	    $time_subset	= "origin.time >= _$opt_s\_ ";
    }

   if ( $opt_e ) {
        if ( $opt_s ) {
            $time_subset	= "origin.time >= _$opt_s\_ && origin.time < _$opt_e\_ " ;
        } else {
            $time_subset	= "origin.time < _$opt_e\_ " ;
        }
   } 

   elog_notify("Subset command is: $time_subset\n") if $opt_V;

    if ( $opt_t ) {
        elog_notify( "Subsetting based on origin.lddate...\n" ) if $opt_V ;
        elog_notify( "... subsetting for all events reviewed after:", $opt_t , "\n")  if $opt_V ;
        if ( ! $time_subset ) {
            $time_subset	= "origin.lddate >= _$opt_t\_ " ;
        } else { 
            $time_subset	= "$time_subset && origin.lddate >= _$opt_t\_ " ;
        } 
        elog_notify("\nFull database subset: dbsubset $database $time_subset \n") if $opt_v ; 
    }

    $filtype	= " ";
 
#
# open up database and lookup tables
#
    @db          = dbopen ( $database, "r") ; 
    
    ( $filename, $refj, $refnetmag, $refstamag ) = &build_dbj ( @db ) ;
    @dbj      = @$refj ; 
    @dbnetmag = @$refnetmag ; 
    @dbstamag = @$refstamag ; 
    
#
# group by event (evid) since I have multiple origins per event. 
#

    if ( $opt_m ) {
        @dborigin_g = dbgroup( @dbj, "time", "evid", "orid", "prefor", "auth", "lat", "lon", "depth", 
                               "mb", "ms", "ml", "nass", "ndef", "algorithm", "dtype", "etype", 
                               "origin.auth", "review", "stime", "sdobs", "smajax", "sminax", 
                               "strike", "sdepth", "magtype", "nsta", "magnitude", "uncertainty", "netmag.auth" ) ;
    } else {
# below worked before I started messing with magnitude info...
        @dborigin_g = dbgroup( @dbj, "time", "evid", "orid", "prefor", "auth", "lat", "lon", "depth", 
                              "mb", "ms", "ml", "nass", "ndef", "algorithm", "dtype", "etype", 
                              "origin.auth", "review", "stime", "sdobs", "smajax", "sminax", "strike", "sdepth");
    }

    @dbevent_g  = dbgroup(@dborigin_g, "evid", "prefor");

    $nevents	= dbquery (@dbevent_g,"dbRECORD_COUNT");
    elog_notify("Number of grouped events is: $nevents	\n") if $opt_v ; 

    if ( $nevents < 1 ) {
        elog_complain("No records after grouping.  \n");
        elog_die("Check for possible dbpath errors.  Exiting.\n");
    }

#
# Now that the filename is determined, open it.
#
    elog_notify( "Bulletin info will be logged to $filename. \n" ) if  $opt_v ; 

    elog_notify( "Done with subsets.  Writing to output file: $filename.\n" ) ;
    
    
#  Database loaded.  Start bulletin processing

    open ( LOG, ">$filename" ) ;
    printf LOG "DATA_TYPE BULLETIN IMS1.0:short \n" ;
    printf LOG " (IRIS AGENCY=\"$pf{agency}\")\n" ;


    for ( $event = 0; $event < $nevents; $event++ ) {
        $dbevent_g[3]	= $event;
        elog_notify( sprintf ( "\nProcessing event#: %d  of %d\n", $event + 1, $nevents ) ) if $opt_v ; 
        ( $evid, $prefor )	= dbgetv( @dbevent_g, qw( evid prefor) ) ;

        elog_notify ( " evid    $evid   prefor   $prefor  \n" ) if $opt_V ;

        @dbevent_b = split( " ", dbgetv( @dbevent_g, "bundle" ) ) ;
        
# print event block header here

        &print_ev_info ( $evid, $prefor, @dbevent_b ) ;
        
#
# find event parameters (get all origin information and add to ORIGIN BLOCK)
#

        &print_origins ( $evid, $prefor, @dbevent_b ) ;

        
        
#         for ( $origin = $dbevent_b[3]; $origin < $dbevent_b[2] ; $origin++ ) {
#             $dbevent_b[3] = $origin;
#             @dborigin_b = split( " ", dbgetv( @dbevent_b, "bundle" ) );
# 
#             ( $orid ) = dbgetv( @dbevent_b, qw (orid) ) ;
# 
# 
# 	# info from netmag table
#             if ( $opt_m ) {
#                 ( $netmagtype, $nsta, $netmag, $magerr )     = dbgetv(@dbevent_b, qw ( magtype nsta magnitude uncertainty ) ) if $opt_m ;
#             } else {
#                 $netmagtype = " " ;
#                 $netmag     = -1.0 ;
#                 $magerr     = 0 ;
#             }
# 
#             $netmagtype = sprintf "%-5s",  $netmagtype ;
#             $netmag     = sprintf "%4.1f", $netmag ;
#             $magerr     = sprintf "%3.1f", $magerr ;
# 	
#             $blank      = " ";
#             $minmaxind  = " ";
# 
# 	# create hash of magnitude info for later print to MAGNITUDE BLOCK
# 
#             $hashname   = $orid ;
# 
#             %$hashname  = ();
#             %$hashname  = (
# 		        netmagtype	=> $netmagtype,
# 		        netmag		=> $netmag,
# 		        magerr		=> $magerr,
# 		        nsta  		=> $nsta  ,
# #		        auth		=> &convert_auth($auth),
# 		        auth		=> $auth,
# 		        orid		=> $orid
#             ) ;
# 
#             push ( @$maglist, $orid ) ;
# 
#             for ( $assoc = $dborigin_b[3] ; $assoc < $dborigin_b[2] ; $assoc++ ) {
#                 $dbj[3]   = $assoc;
#                 ($delta, $artime)     = dbgetv(@dbj, qw ( assoc.delta arrival.time));
# 
# 	# get all info and put into hash for prefor
#                 if ( $orid == $prefor ) {	   
#     # adding chan, net, and deltime for SUB-BLOCK
#                     ( $sta, $chan, $net, $loc, $deltime, $dist, $evaz, $phase, $tres, $azim, $azres, $slodef ) = dbgetv( @dbj, qw ( assoc.sta chan snet loc deltim delta esaz iphase timeres delta azres slodef) )  ;
# 
# 		# info from arrival table
#                     ($atime, $slow, $sres, $snr, $amp, $per, $fm, $arid) = dbgetv(@dbj, qw ( arrival.time arrival.slow delslo snr amp per fm arrival.arid )) ;
# 
#                     elog_notify("      arrival time     %s \n", strydtime( $atime ) ) if $opt_V ;
# 
#                     $arrtime_ms	= epoch2str( $atime, "%s") ;
# 
# 		# get precision and rounding correct 
#                     if ($arrtime_ms == 1000) {
#                         $arrtime_ms = 999;
#                     }
# 
#                     $arrtime	= epoch2str($atime, "%H:%M:%S") . ".$arrtime_ms"; 
#                     $arrtimesb	= epoch2str($atime, "%Y/%m/%d");
# 
#                     $azim 		= sprintf "%5.1f", $azim;
#                     $dist		= sprintf "%6.2f", $delta;
# 
#                     if ($azres == -999.0) {  
#                         $azres = " " ;
#                     }	
# 
#                     if ($slow  == -1.0) {  
#                         $slow  = " " ;
#                     }	
# 
#                     if ($sres == -1.0) {  
#                         $sres = " " ;
#                     }	
# 
#                     if ($snr == -1.0) {  
#                         $snr  = " " ;
#                     } elsif ($snr >= 999) {
#                         elog_notify("Truncating SNR\n") if $opt_V  ;
#                         $snr = 999.9 ;
#                     } else {
#                         $snr  = sprintf "%5.1f", $snr ;	
#                     }	
# 
#                     if ($amp  == -1.0) {  
#                         $amp  = " " ;
#                     } else {	
#                         $amp  = sprintf "%9.1f", $amp ;	
#                     }
# 
#                     if ($per  == -1.0) {  
#                         $per  = " " ;
#                     } else {	
#                         $per  = sprintf "%5.2f", $per ;	
#                     }
# 
#                     if ($deltime == -1.0) {  
#                         $deltime = " " ;
#                     } else {	
#                         $deltime = sprintf "%5.2f", $deltime ;	
#                     }
# 
#                     if ($loc =~ /-/) {
#                         $loc = " " ;
#                     }
# 
#                     $tasdef	= "___" ;
# 
#                     if ($fm !~ /-/ ) {
#                         $pickinfo	= "m" . substr($fm,0,1) . "_";
#                     } else {
#                         $pickinfo	= "m__";	# m is used because we only send reviewed solutions, no auto-picks
#                     }
# 
#                     $maginfo = $blank;
# 
# # poorly (un)coded magnitude reporting
#                     if ($opt_m) {	
#                         ( $magtype, $stamag, $mag_auth ) = dbgetv ( @dbj, qw ( stamag.magtype stamag.magnitude netmag.auth ) )  ;
#                         $stamag  = sprintf "%4.1f", $stamag ;	
#                         elog_notify( "Magtype: $magtype.  Stamag: $stamag.  Mag_auth: $mag_auth.  Auth: $auth\n" );
#                         if ( $orauth =~ /$pf{mag_origin_auth}/ && $mag_auth =~ /$pf{mag_netmag_auth}/ ) {
#                             elog_notify( "Looking good.  Matches origin.auth and netmag.auth!\n" );
#                             if ( exists $pf{accept_magtype}{$magtype} )  {
#                                 elog_notify( "Woo Hoo!  Found a magnitude matcherooni!\n" );
#                                 $maginfo = $magtype . " " . $stamag ;
#                             } else { 
#                                 elog_complain( "Drat.  $pf{accept_magtype}{$magtype} did not exist!\n" );
#                                 $magtype = "";
#                                 $stamag = "";
#                             }
#                         } else {
#                             elog_complain( "No Dice.  Auth, $orauth doesn't match mag subsets, $pf{mag_origin_auth} or $pf{mag_netmag_auth}.\n" );
#                             $magtype = "" ;
#                             $stamag = "" ;
#                         }
#                     }
# 
# 	# put this information in a hash... using arid as main key
# 
#                     $hashname = $arid ;
# 
#                     %$hashname = ();
#                     %$hashname = (
#                         sta         => $sta ,
#                         chan        => $chan,
#                         filtype     => $filtype,
#                         deltime     => $deltime,
#                         net         => $net,
#                         loc         => $loc,
#                         dist        => $dist , 
#                         evaz        => $evaz , 
#                         phase       => $phase ,
#                         tres        => $tres, 
#                         azim        => $azim ,
#                         azres       => $azres ,
#                         slodef      => $slodef ,
#                         magtype     => $magtype ,
#                         magnitude   => $stamag,
#                         arrtimesb   => $arrtimesb ,
#                         arrtime     => $arrtime ,
#                         slow        => $slow ,
#                         sres        => $sres ,
#                         snr         => $snr ,
#                         amp         => $amp ,
#                         per         => $pre ,
#                         fm          => $fm , 
#                         pickinfo    => $pickinfo, 
#                         arid        => $arid  
#                     );
# 		
#                     push( @$prefor, $arid ) ;
# 
#                 } # end of orid == prefor
# 
#             } # end of loop over each assoc
# 
# 
# 
#             &print_origins ( $evid, $prefor, @dbevent_b ) ;
#         
#         } # end of loop over each origin.  Should have prefor information by now

        &print_mags ( $evid, \@dbevent_b, \@dbnetmag ) ;
    
#     
# # In theory, a magnitude block should go here... but I am still in the middle of coding it 
# #	print "Printing MAGNITUDE BLOCK HEADER\n";
#         printf LOG "\n%9s%2s%3s%1s%4s%1s%6s%6s%6s\n", "Magnitude",$blank,"Err",$blank,"Nsta",$blank,"Author",$blank,"OrigID" if $opt_m;
# 
# #	print "Printing MAGNITUDE BLOCK DATA\n";
# 
# 
# # loop over all orids in @$maglist and only print out those that match $pf{mag_origin_auth}
#         if ( $opt_m ) {
#             foreach $value (@$maglist) {
#                 elog_notify("Value: $value.  auth: $$value{auth} vs $pf{mag_origin_auth}.  $$value{netmagtype} and $$value{nsta}\n");
#                 if ( ( $$value{auth} =~ /$pf{mag_origin_auth}/) && ($$value{netmagtype} !~ /-|^s/ || $$value{nsta} != -1.0) ) {  # don't print if no netmag values
#                     elog_notify("Found a magnitude to print to MAG BLOCK.\n");
#                     printf LOG "%-5s%s%4.1f%1s%3.1f%1s%4s%1s%-9s%1s%8s\n", $$value{netmagtype}, $minmaxind,$$value{netmag},$blank,$$value{magerr},$blank,$$value{nsta},$blank,convert_auth($$value{auth}),$blank,$$value{orid};
#                 } else {
#                     elog_notify("Not printing magnitude for author: $$value{auth}\n");
#                 }		
#             }
# 	    }
# 	    

        &print_arrivals ( $evid, $prefor, \@dbj, \@dbstamag ) ;
                    
    } #end of loop over each event 

#print LOG "End of run\n";

    dbclose @db;
    close(LOG);
}

sub convert_auth {
    my ( $auth2c ) = @_ ;
    my ( $auth ) ; 

	given( $auth2c ) {
	    when (/ANF.*/)      { $auth	= "ANF"; }
	    when (/ANZA.*/)     { $auth	= "ANZA"; }
	    when (/CERI.*/)     { $auth	= "CERI"; }
	    when (/cit.*/)      { $auth	= "SCEDC"; }
	    when (/ISC/)        { $auth	= "ISC" ; }
	    when (/MTECH.*/)    { $auth	= "MTECH"; }
	    when (/NBE.*/)      { $auth	= "UNR"; }
	    when (/NCEDC.*/)    { $auth	= "NCEDC"; }
	    when (/NCSN.*/)     { $auth	= "NCEDC"; }
	    when (/PDE/)        { $auth	= "PDE" ; }
	    when (/PDE-Q/)      { $auth	= "PDE-Q" ; }
	    when (/PDE-W/)      { $auth	= "PDE-W" ; }
	    when (/PNSN.*/)     { $auth	= "PNSN"; }
	    when (/QED_weekly/) { $auth	= "PDE-W" ; }
	    when (/SCEDC/)      { $auth	= "SCEDC"; }
	    when (/SCSN.*/)     { $auth	= "SCEDC"; }
	    when (/UCSD.*/)     { $auth	= "ANZA"; }
	    when (/UNR.*/)      { $auth	= "UNR"; }
	    when (/UTAH.*/)     { $auth	= "UUSS"; }
	    when (/UUSS.*/)     { $auth	= "UUSS"; }
	    default             { $auth = "UNKNWN"; }
	}

	elog_notify("converted auth is: $auth\n") if $opt_V;
	return $auth; 
}

sub map_etype { # $evtype = map_etype ( $etype ) ; 
    my ( $etype ) = @_ ;
    my ( $evtype ) ; 
    my ( %emap ) ;
	
	%emap = (
         L => "ke",
		 l => "ke",
		le => "ke",
		LE => "ke",
		 U => "uk",
		UK => "uk",
		 u => "uk",
		uk => "uk",
		 q => "km",
		 Q => "km",
		qb => "km",
		QB => "km",
		 T => "ke",
		 t => "ke",
		ts => "ke",
		TS => "ke",
		 R => "ke",
		 r => "ke",
		re => "ke",
		RE => "ke",
		 N => "kn",
		 n => "kn",
		nt => "kn",
		NT => "kn",
		 o => " ",
		 "-" => " "
	);

	$evtype = $emap{$etype}; 
	elog_notify("etype is: $evtype\n") if $opt_V;
	return ( $evtype ) ; 
	
}

sub new_filename {  # $filename = &new_filename ( $filename ) ; 
    my ( $filename ) = @_ ;
    my ( $prefix, $suffix ) ; 
    
    if ( index( $filename, "." ) < 0 ) {
        elog_notify("   Attempting to change filename from: $filename to: ") if $opt_V; 
        $filename = $filename . ".1";
        elog_notify("  $filename \n") if $opt_V; 
    } elsif ( index( $filename, "." ) >= 1) {
        elog_notify("   Attempting to change filename from: $filename to: ") if $opt_V ; 
        $prefix = substr( $filename, 0, rindex( $filename, "." ) ) ;
        $suffix = substr( $filename, rindex( $filename, "." ) + 1 );

        if ( $suffix =~ /^[0-9]+$/ ) { #purely an integer
            $filename = $prefix . "." . ++$suffix;
            elog_notify( "  $filename \n" ) if $opt_V ; 
        }  else {
            $filename = $filename . ".1";
            elog_notify( "  $filename \n" ) if $opt_V ; 
            elog_complain( "Error: filename already exists.\n" ) if $opt_V;
            elog_notify( "Modifying output to $filename.\n" ) if $opt_V;
        }
    }
    return ( $filename ) ; 
}

sub build_dbj { # ( $filename, $refj, $refnetmag, $refstamag ) = &build_dbj ( @db ) ; 
    my ( @db ) = @_ ;
    
    my ( $filename, $mysubset, $nrecs, $ortime, $startdy, $startmo, $startyr, $time_subset ) ; 
    my ( @dbarrival, @dbassoc, @dbevent, @dbj, @dbnetmag, @dborigerr, @dborigin, @dbschanloc, @dbsnetsta, @dbstamag, @dmcbull, @trackdb ) ; 

    @dborigin    = dblookup( @db, "", "origin",   "", "" ) ;
    @dbassoc     = dblookup( @db, "", "assoc",    "", "" ) ;
    @dbarrival   = dblookup( @db, "", "arrival",  "", "" ) ;
    @dborigerr   = dblookup( @db, "", "origerr",  "", "" ) ;
    @dbevent     = dblookup( @db, "", "event",    "", "" ) ;
    @dbnetmag    = dblookup( @db, "", "netmag",   "", "" ) ;
    @dbstamag    = dblookup( @db, "", "stamag",   "", "" ) ;
    @dbsnetsta   = dblookup( @db, "", "snetsta",  "", "" ) ;
    @dbschanloc  = dblookup( @db, "", "schanloc", "", "" ) ;

    if ( ! dbquery( @dborigin, "dbRECORD_COUNT" ) ) {
        elog_die( "No records in origin table.  Exiting.\n" );
    } else {
        elog_notify( sprintf ( "%d origin records before any subsets. \n", dbquery( @dborigin, "dbRECORD_COUNT" ) ) ) if ( $opt_V ) ;
    }
#
# subset origin table based on command line arguments 
#

    @dborigin = dbsubset( @dborigin, "$time_subset" ) if $time_subset ; 
    $nrecs	  = dbquery ( @dborigin, "dbRECORD_COUNT" ) ;
    elog_notify( "$nrecs records after subsetting for origin time, author, and possibly lddate. \n" ) if $opt_V ;

    if ( ! $nrecs ) {
        elog_die( "No records after time subset.  Exiting.\n" ) ;
    }

#
# take only reviewed origins
#

    if ( $opt_y ) {
        $nrecs	    = dbquery ( @dborigin, "dbRECORD_COUNT" );
        elog_notify( "$nrecs records before subsetting for reviewed origins. \n" ) if ( $opt_v ) ;
        @dborigin	= dbsubset( @dborigin, "review=='y'" ) ;     
        $nrecs	    = dbquery ( @dborigin, "dbRECORD_COUNT" ) ;

        if ( ! $nrecs ) {
            elog_die( "No records in origin table after reviewed origin subset.  Exiting.\n" ) ;
        } else {
            elog_notify( "$nrecs records after  subsetting for reviewed origins. \n" ) if ( $opt_v ) ;
        }
    }

#
# reject certain origin authors (i.e. those that are automatic solutions)
#

# get list from pf file and construct subset expression, $pf{auth_reject}

    elog_notify( "author reject set to: $pf{auth_reject}\n" ) if ( $opt_V ) ;
    $mysubset = "auth !~ /" . $pf{auth_reject} . "/" ;
    @dborigin = dbsubset( @dborigin, $mysubset ) ;
    $nrecs	  = dbquery ( @dborigin, "dbRECORD_COUNT" ) ;
    if ( !$nrecs ) {
        elog_die( "No records in origin table after author reject subset.  Exiting.\n" ) ;
    } else {
        elog_notify( "$nrecs records after removing author rejects. \n" ) if ( $opt_v ) ;
    }

#
# Frank's suggestion to deal with problem where automatic solutions 
# from dborigin2orb/orb2dbt get added to database as prefor, but are 
# not reviewed (problem for rt databases)
#
#  

    @dbj     = dbjoin  ( @dbevent, @dborigin ) ;
    $nrecs   = dbquery ( @dbj, "dbRECORD_COUNT" ) ;
    elog_notify( "$nrecs records after joining event origin. \n" ) if $opt_v ;
   
    @dbj     = dbsubset  ( @dbj, "prefor == orid" ) ;
    @dbevent = dbseparate( @dbj, "event" ) ;
    $nrecs	 = dbquery   ( @dbj, "dbRECORD_COUNT" ) ;
    elog_notify( "$nrecs records after separating \"y\" prefor events. \n" ) if $opt_v ;
   
#
# determine time of first origin to use for filename check
#
# sort it first to get proper time
#

    @dborigin	= dbsort( @dborigin, "origin.time" ) ;

    $dborigin[3] = 0 ;
    $ortime  = dbgetv( @dborigin, qw( time ) ) ;
    $startyr = epoch2str( $ortime, "%Y" ) ;
    $startmo = epoch2str( $ortime, "%m" ) ;
    $startdy = epoch2str( $ortime, "%d" ) ;

    if ($opt_l) {
        $filename = "$opt_l";
    } else {
        $filename = "$pf{ims_dir}/$startyr\_$startmo\_$startdy\_$pf{agency}"."_IMS";
        elog_notify( "filename is: $filename.  \n" ) if $opt_V ;
        elog_notify( "Now checking for $pf{ims_dir}  existance.\n" ) if $opt_V;
        if (! -d $pf{ims_dir}) {
            elog_complain( "$pf{ims_dir} does not exist.  Creating.\n" ) if ($opt_v || $opt_V);
            mkpath "$pf{ims_dir}" ;
        }
    }


# check to see if filename already exists in save area

    while (-e $filename) {  
        elog_complain("   Duplicate filename. Attempting a fix. ") if $opt_v; 

        $filename = &new_filename ( $filename ) ;
    }

# check to see if filename already exists in tracking db
  
    if (-e $opt_d) {
        @trackdb 	= dbopen ( $opt_d, "r") ; 
        @dmcbull	= dblookup(@trackdb,"","dmcbull","","") ;
        
        while ( dbfind ( @dmcbull, "dfile =~ /$filename/", -1 ) != -2 ) {
            $filename = &new_filename ( $filename ) ;
        }

        dbclose ( @trackdb ) ; 
    } 


#
# join in assoc, arrival, and event tables, sort and prepare groups for reporting
#

    @dbj      = dbjoin  ( @dbevent, @dborigin );
    $nrecs    = dbquery ( @dbj, "dbRECORD_COUNT");
    elog_notify("$nrecs records after joining ev ent origin.") if $opt_V;

    @dbj      = dbjoin  ( @dbj, @dbassoc );
    $nrecs    = dbquery ( @dbj, "dbRECORD_COUNT" );
    elog_notify("$nrecs records after joining event origin assoc.") if $opt_V;

    @dbj      = dbjoin  ( @dbj, @dbarrival ) ;
    $nrecs    = dbquery ( @dbj, "dbRECORD_COUNT" );
    elog_notify("$nrecs records after joining event origin assoc arrival.") if $opt_V;

    @dbj      = dbjoin  ( @dbj, @dbsnetsta ) ;
    @dbj      = dbjoin  ( @dbj, @dbschanloc ) ;
    @dbj      = dbsubset( @dbj, "arrival.chan == schanloc.chan" ) ;
    $nrecs	  = dbquery ( @dbj, "dbRECORD_COUNT" );
    elog_notify( "$nrecs records after joining event origin assoc arrival snetsta schanloc." ) if $opt_V;

    if ( ! $nrecs ) { 
        elog_die( "No records after joining event origin assoc arrival snetsta and schanloc.  Exiting." );
    }

    @dbj      = dbjoin  ( @dbj, @dborigerr, "-outer" ) ;
    $nrecs	  = dbquery ( @dbj, "dbRECORD_COUNT" );
    elog_notify( "$nrecs records after joining origerr" ) if $opt_V;

#     if ( $opt_m ) { 
#         if ( dbquery ( @dbnetmag, "dbRECORD_COUNT")) {
# 	        @dbj    = dbjoin (@dbj, @dbnetmag, -outer, "orid");
# 	        $nrecs	= dbquery (@dbj,"dbRECORD_COUNT");
# 	        elog_notify("", dbquery (@dbj, "dbRECORD_COUNT"), " records after joining netmag \n") if $opt_V;
#         }
# 
#         if ( dbquery ( @dbstamag, "dbRECORD_COUNT")) {
# 	        @dbj    = dbjoin (@dbj, @dbstamag, -outer, "orid", "sta");
# 	        $nrecs	= dbquery (@dbj,"dbRECORD_COUNT");
# 	        elog_notify("", dbquery (@dbj, "dbRECORD_COUNT"), " records after joining stamag \n") if $opt_V;
#         }
#     }

    @dbj      = dbsort  ( @dbj, "origin.time", "origin.auth", "arrival.time" ) ;
    $nrecs	  = dbquery ( @dbj, "dbRECORD_COUNT" ) ;
    elog_notify("$nrecs records after sorting for origin.time, and arrival.time. ") if $opt_V;
    if ( ! $nrecs ) { 
        elog_die("No records after sorting for origin.time and arrival.time.  Exiting.");
    }
    return ( $filename, \@dbj, \@dbnetmag, \@dbstamag ) ;
}

sub print_ev_info { # &print_ev_info ( $evid, $prefor, @dbevent_b ) ;
    my ( $evid, $prefor, @dbevent_b ) = @_ ;
    my ( $blank, $gregion, $lat, $lon, $orid, $origin ) ;

    for ( $origin = $dbevent_b[3]; $origin < $dbevent_b[2] ; $origin++ ) {
        $dbevent_b[3]         = $origin ;
        ( $orid, $lat, $lon ) = dbgetv( @dbevent_b, qw ( orid lat lon) ) ;
        elog_notify ("print_ev_info	evid	$evid	orid	$orid	prefor	$prefor	lat	$lat	lon	$lon	\n") if $opt_V ;
        $gregion              = grname( $lat, $lon ) ;
        last if ( $orid == $prefor ) ;
    }

    printf LOG "\n\nEVENT $evid $gregion\n";
    return ;
}

sub print_origins { # &print_origins ( $evid, $prefor, @dbevent_b ) ;
    my ( $evid, $prefor, @dbevent_b ) = @_ ;
    
    my ( $alg, $auth, $blank, $depth, $dtype, $etype, $fixed, $lat, $lon, $maxdelta, $mindelta, $ndef, $oDY, $oMO, $oYR, $ohour, $omin, $oms, $omsec, $orauth, $orid, $origin, $otime, $prefauth, $sdepth, $sdobs, $smajax, $sminax, $stime, $strike ) ;
    my ( @dborigin_b ) ;
    $blank      = " ";
    
# ORIGIN BLOCK (HEADER)
    printf LOG "%3s%s%7s%s%8s%s%3s%s%1s%s%1s%s", $blank,"Date",$blank,"Time",$blank,"Err",$blank, "RMS", $blank,"Latitude", $blank,"Longitude";
    printf LOG "%2s%s%2s%s%2s%s%1s%s%3s%s%1s%s", $blank,"Smaj",$blank,"Smin",$blank,"Az",$blank,"Depth",$blank,"Err";
    printf LOG "%s%1s%s%1s%s%2s%s%2s%s%1s%s%3s%s%6s%s\n", "Ndef",$blank,"Nsta",$blank,"Gap",$blank,"mdist",$blank,"Mdist", $blank,"Qual",$blank,"Author",$blank,"OrigId";

    for ( $origin = $dbevent_b[3]; $origin < $dbevent_b[2] ; $origin++ ) {
        $dbevent_b[3]  = $origin ;
        @dborigin_b    = split( " ", dbgetv( @dbevent_b, "bundle" ) );
        
# info from origin table

        ( $orid, $otime, $lat, $lon, $depth, $ndef, $etype, $dtype, $alg, $prefauth ) = dbgetv( @dbevent_b, qw ( orid time lat lon depth ndef etype dtype algorithm auth ) );
        elog_notify ( "print_origins	evid	$evid	orid	$orid	prefor	$prefor" ) if $opt_V ;
        elog_notify ( sprintf ( "	time	%s	lat	$lat	lon	$lon	depth	$depth	alg	$alg", strydtime($otime) ) ) if $opt_V ;

        $auth		= dbgetv( @dborigin_b, qw ( origin.auth ) ) ; 
        $orauth		= $auth ;
        elog_notify("   prefauth     $prefauth \n") if $opt_V ;
        elog_notify("       auth     $auth \n") if $opt_V ;

	# info from origerr table
        ( $stime, $sdobs, $smajax, $sminax, $strike, $sdepth )     = dbgetv( @dbevent_b, qw ( stime sdobs smajax sminax strike sdepth ));

        if ( $smajax > 99.9 ) {  
            $smajax = 99.9 ;
        }	

        if ( $sminax > 99.9 ) {  
            $sminax = 99.9 ;
        }	

        if ( $sdepth > 99.9 ) {  
            $sdepth = 99.9 ;
        }	

	# info from assoc table

        if ( $orid == $prefor ) {
            $mindelta = dbex_eval (  @dbevent_b, "min( delta )" ) ;
            $maxdelta = dbex_eval (  @dbevent_b, "max( delta )" ) ;
        }
        
 # PRINT REMAINDER of ORIGIN BLOCK DATA 
        $oYR		= epoch2str($otime,"%Y")  ;
        $oMO		= epoch2str($otime,"%m")  ;
        $oDY		= epoch2str($otime,"%d")  ;
        $ohour		= epoch2str($otime, "%H") ;
        $omin		= epoch2str($otime, "%M") ;
        $oms 		= epoch2str($otime, "%S") ;
        $omsec		= epoch2str($otime, "%s") ;

	# get percision and rounding correct 
        if ($omsec == 1000) {
                $omsec = 999 ;
        }
        $omsec		= $omsec/10 ;
        $omsec		= sprintf "%2d", $omsec ;

        if ($omsec < 10) {
                $omsec	= "0" . chop($omsec) ;	
        }

        $fixed = " " ;

        if ($dtype =~/g/) { 
            $fixed = "f" ; 
        } else {
            $fixed = $blank ;
        }

#print "Auth is: $auth\n";
#        $auth = &convert_auth($auth); 

        if ( $orauth !~ /$pf{match_origerr_auth}.*/ ) {
            $stime  = $blank ;
            $sdobs  = $blank ;  
            $smajax = $blank ;
            $sminax = $blank ; 
            $strike = $blank ; 
            $sdepth = $blank ; 
        } else { 
            $strike = sprintf "%3d", $strike;
            $sdepth = sprintf "%4.1f", $sdepth;
        }

        if ( $ndef == -1 || $ndef == 0 ) {
            $ndef = $blank ;
        } 

        $auth = &convert_auth($auth); 

        $etype = &map_etype ( $etype );

        if ( $opt_v ) {
            printf "%4s/%2s/%2s %2s:%2s:%s.%s%1s",  $oYR, $oMO, $oDY, $ohour, $omin, $oms, $omsec, $blank  ;
            printf " %5.2f %5.2f",  $stime, $sdobs  ; 
            printf " %8.4f %9.4f%1s %4.1f %5.1f %3s",  $lat, $lon, $fixed, $smajax, $sminax, $strike  ; 
            printf " %5.1f%1s %4.1f %4s %4s %3s", $depth, $blank, $sdepth, $ndef, $blank, $blank  ; 
            printf " %6.2f %6.2f %1s %1s %2s %9s %8s\n", $mindelta, $maxdelta, $blank, $blank, $etype, $auth, $orid  ; 
        } 

# ORIGIN BLOCK (DATA)
        printf LOG "%4s/%2s/%2s %2s:%2s:%s.%s%1s",  $oYR, $oMO, $oDY, $ohour, $omin, $oms, $omsec, $blank;

        if ($orauth =~ /$pf{match_origerr_auth}.*/) {
            printf LOG " %5.2f %5.2f",  $stime, $sdobs ; 
            printf LOG " %8.4f %9.4f%1s ", $lat, $lon, $fixed ;
            printf LOG "%4.1f %5.1f %3s", $smajax, $sminax, $strike ; 
            printf LOG " %5.1f%1s %4.1f %4s %4s %3s", $depth, $blank, $sdepth, $ndef, $blank, $blank; 
        } else {
            printf LOG " %5s %5s",  $stime, $sdobs ; 
            printf LOG " %8.4f %9.4f%1s ", $lat, $lon, $fixed ;
            printf LOG "%4s %5s %3s", $smajax, $sminax, $strike ;
            printf LOG " %5.1f%1s %4s %4s %4s %3s", $depth, $blank, $sdepth, $ndef, $blank, $blank; 
        }
        printf LOG " %6.2f %6.2f %1s %1s %2s %9s %8s\n", $mindelta, $maxdelta, $blank, $blank, $etype, $auth, $orid ; 
	
	# Latest officially sanctioned way to determine origin supremacy 
        if ( $orid == $prefor ) { 
            printf LOG " %s \n", "(#PRIME)" ; 
        }
        
    }

    return ;
}

sub print_mags { # &print_mags ( $evid, \@dbevent_b, \@dbnetmag ) ;
    my ( $evid, $refb, $refn ) = @_ ;
    
    my ( $auth, $blank, $magerr, $magnitude, $magtype, $minmaxind, $netmag, $netmagtype, $nsta, $orid, $origin, $row, $uncertainty ) ;
    my ( @dbevent_b, @dbnetmag, @dborigin_b, @dbscr, @rows ) ;
    $blank      = " " ;
    $minmaxind  = " ";
    
    @dbevent_b = @$refb ; 
    @dbnetmag  = @$refn ;
    @dbscr     = dblookup( @dbnetmag, 0, "netmag", 0, "dbSCRATCH" ) ; 
    

#	print "Printing MAGNITUDE BLOCK DATA\n";


    for ( $origin = $dbevent_b[3]; $origin < $dbevent_b[2] ; $origin++ ) {
        $dbevent_b[3]  = $origin ;
        @dborigin_b    = split( " ", dbgetv( @dbevent_b, "bundle" ) );
        
# info from origin table

        ( $orid, $auth ) = dbgetv( @dborigin_b, qw ( orid origin.auth ) ) ;
        
        elog_notify ( "print_mags	orid	$orid	auth	$auth	pf\{match_origerr_auth\}	$pf{match_origerr_auth}" ) if $opt_V ; 
        
        if ( $auth =~ /$pf{match_origerr_auth}/ ) {
            dbputv ( @dbscr, "orid", $orid ) ;
            @rows = dbmatches( @dbscr, @dbnetmag, "netmag", "orid" ) ;
            elog_notify ( "orid	$orid	nrows	$#rows " ) if $opt_V ;
            if ( $#rows > -1 ) {
 #	print "Printing MAGNITUDE BLOCK HEADER\n";
                printf LOG "\n%9s%2s%3s%1s%4s%1s%6s%6s%6s\n", "Magnitude",$blank,"Err",$blank,"Nsta",$blank,"Author",$blank,"OrigID";
                foreach $row ( @rows) {
                    $dbnetmag[3] = $row ;
                    ( $magtype, $magnitude, $uncertainty, $nsta, $auth ) = dbgetv ( @dbnetmag, qw ( magtype magnitude uncertainty nsta auth ) ) ;
                    $netmagtype = sprintf "%-5s",  $pf{accept_magtype}{ $magtype } ;
                    $netmag     = sprintf "%4.1f", $magnitude ;
                    $magerr     = sprintf "%3.1f", $uncertainty ;

                    printf LOG "%-5s%s%4.1f%1s%3.1f%1s%4s%1s%-9s%1s%8s\n", $netmagtype, $minmaxind, $netmag,$blank,$magerr,$blank,$nsta,$blank,$auth,$blank,$orid;
                }
            }
        }
    }
    
    return ; 

}

sub print_arrivals { # &print_arrivals ( $evid, $prefor, \@dbj, \@dbstamag ) ;
    my ( $evid, $prefor, $refj, $refs ) = @_ ;
    my ( $amp, $arid, $arrtime, $arrtime_ms, $arrtimesb, $atime, $auth, $azim, $azres, $blank, $chan, $deltim, $dist, $evaz, $filtype, $first_row, $fm, $iphase, $last_row, $loc, $magnitude, $magtype, $minmaxind, $mtype, $net, $per, $phase, $pickinfo, $slodef, $slow, $snr, $sres, $sta, $stamag, $tasdef, $tres, $value ) ;
    my ( @dbj, @dbscr, @dbstamag ) ;

    $blank      = " ";
    $minmaxind  = " ";
    
    @dbj       = @$refj ; 
    @dbstamag  = @$refs ;
    @dbscr     = dblookup( @dbstamag, 0, "stamag", 0, "dbSCRATCH" ) ; 

#	print "Printing PHASE BLOCK HEADER\n";
    printf LOG "\n%s%5s%s%2s%s%1s%s%8s%s%6s%s", "Sta",$blank,"Dist",$blank,"EvAZ",$blank,"Phase",$blank,"Time",$blank,"TRes";
    printf LOG "%2s%s%1s%s%3s%s%3s%s%1s%s%3s", $blank,"Azim",$blank,"Azres",$blank,"Slow",$blank,"Sres",$blank,"Def",$blank;
    printf LOG "%s%7s%s%3s%s%1s%s%1s%s%4s%s\n", "SNR",$blank,"Amp",$blank,"Per",$blank,"Qual",$blank,"Magnitude",$blank,"ArrID";

#	print "Printing PHASE BLOCK DATA\n";

    $first_row = dbfind ( @dbj, "orid == $prefor" , -1 ) ;
    $last_row  = dbfind ( @dbj, "orid == $prefor" , dbquery( @dbj, "dbRECORD_COUNT" ), "reverse" ) ;
    
    elog_notify ( "print_arrivals	evid	$evid	prefor	$prefor	first row	$first_row	last row	$last_row" ) if $opt_V ;
        
    for ( $dbj[3] = $first_row ; $dbj[3] <= $last_row ; $dbj[3]++ ) {
        ( $sta, $deltim, $dist, $evaz, $phase, $tres, $azim, $azres, $slodef, $auth ) = dbgetv( @dbj, qw ( assoc.sta deltim delta esaz iphase timeres seaz azres slodef origin.auth ) )  ;

		# info from arrival table
        ( $atime, $slow, $sres, $snr, $amp, $per, $fm, $arid) = dbgetv(@dbj, qw ( arrival.time arrival.slow delslo snr amp per fm arrival.arid )) ;

        elog_notify("      arrival time     %s \n", strydtime( $atime ) ) if $opt_V ;

        $arrtime_ms	= epoch2str( $atime, "%s") ;

		# get precision and rounding correct 
        if ($arrtime_ms == 1000) {
            $arrtime_ms = 999;
        }

        $arrtime	= epoch2str($atime, "%H:%M:%S") . ".$arrtime_ms"; 

        $azim 		= sprintf "%5.1f", $azim;
        $dist		= sprintf "%6.2f", $dist;

        if ($azres == -999.0) {  
            $azres = " " ;
        }	

        if ($slow  == -1.0) {  
            $slow  = " " ;
        }	

        if ($sres == -1.0) {  
            $sres = " " ;
        }	

        if ($snr == -1.0) {  
            $snr  = " " ;
        } elsif ($snr >= 999) {
            elog_notify("Truncating SNR\n") if $opt_V  ;
            $snr = 999.9 ;
        } else {
            $snr  = sprintf "%5.1f", $snr ;	
        }	

        if ($amp  == -1.0) {  
            $amp  = " " ;
        } else {	
            $amp  = sprintf "%9.1f", $amp ;	
        }

        if ($per  == -1.0) {  
            $per  = " " ;
        } else {	
            $per  = sprintf "%5.2f", $per ;	
        }

#         $tasdef	= "___" ;
        $tasdef	= "" ;

        if ($fm !~ /-/ ) {
            $pickinfo	= "m" . substr($fm,0,1) . "_";
        } else {
            $pickinfo	= "m__";	# m is used because we only send reviewed solutions, no auto-picks
        }
        
        $magtype    = "" ;
        $magnitude  = "" ;
        
        if ( $auth =~ /$pf{match_origerr_auth}/ )  {
            $dbstamag[3] = dbfind ( @dbstamag, " ( orid == $prefor ) && ( sta =~ /$sta/ ) ", -1 ) ;
            elog_notify ( "print_arrivals	( orid == $prefor ) && ( sta =~ /$sta/ ) auth	$auth	$pf{match_origerr_auth}	$dbstamag[3]" ) if $opt_V;
            if ( $dbstamag[3] != -2 ) {
                ( $mtype, $stamag ) = dbgetv ( @dbstamag, qw ( magtype magnitude ) ) ;
                if ( exists $pf{accept_magtype}{ $mtype } )  { 
                    $magtype   = $pf{accept_magtype}{ $mtype } ;
                    $magnitude = sprintf "%4.1f", $stamag ;
                }
            }
        } 
        
        printf LOG "%-5s %6.2f %5.1f %-8s %12s %5.1f %5.1f %5s %6s %6s %3s %5s %9s %5s %3s %-5s%s%4s %8s \n",  
               $sta, $dist, $evaz, $phase, $arrtime, $tres, $azim, $azres, $slow, $sres, $tasdef, $snr, 
               $amp, $per, $pickinfo, $magtype, $minmaxind, $magnitude, $arid ; 
    }
    
    
    
# PHASE INFO SUB-BLOCK
#	print "Printing PHASE SUB-BLOCK HEADER \n";

    printf LOG "\n%s%6s%s%1s%s%1s%s%1s%s%1s%s", "Net",$blank,"Chan",$blank,"F",$blank,"Low_F",$blank,"HighF",$blank,"AuthPhas";
    printf LOG "%4s%s%5s%s%1s%s%1s%s%1s%s%2s", $blank,"Date",$blank,"eTime",$blank,"wTime",$blank,"eAzim",$blank,"wAzim",$blank;
    printf LOG "%s%1s%s%6s%s%2s%s%1s%s%2s%s%4s%s\n", "eSlow",$blank,"wSlow",$blank,"eAmp",$blank,"ePer",$blank,"eMag",$blank,"Author",$blank,"ArrID";

    for ( $dbj[3] = $first_row ; $dbj[3] <= $last_row ; $dbj[3]++ ) {

        ( $net, $chan, $loc, $iphase, $atime, $deltim, $arid ) = dbgetv( @dbj, qw ( snet fchan loc iphase arrival.time deltim arid ) )  ;

        $arrtimesb	= epoch2str($atime, "%Y/%m/%d");

        if ($deltim == -1.0 ) {  
            $deltim = 0.0 ;
        } else {	
            $deltim = sprintf "%5.2f", $deltim ;	
        }

        if ($loc =~ /-/) {
            $loc = "" ;
        }

        printf LOG "%-9s %3s %1s %5s %5s %-8s %10s %6.3f %5s %5s %5s %6s %5s %9s %5s %3s %8s %8s\n",  $net, $chan, $filtype, $blank, $blank, $iphase, $arrtimesb, $deltim, $blank, $blank, $blank, $blank, $blank, $blank, $blank, $blank, $pf{agency}, $arid; 
		# print the totally moronic comment lines that make reading this file impossible
        if (! $loc ) { 
            printf LOG " %s%s%s  \n", "(IRIS FDSNNETWORKCODE=\"", $net, "\")" ; 
        } else {
            printf LOG " %s%s%s%2s%s  \n", "(IRIS FDSNNETWORKCODE=\"", $net, "\" FDSNLOCATIONID=\"", $loc, "\")" ;
        }

    }

}
