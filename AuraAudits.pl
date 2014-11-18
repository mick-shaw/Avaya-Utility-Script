#!/usr/bin/perl -w
use strict;

require "./cli_ossi.pm";
import cli_ossi;

use Getopt::Long;
use Pod::Usage;
use Net::Nslookup;
use Net::MAC;
use Data::Dumper;

###########################################################
#
# 11/17 - Left off with this issue:
# TODO: The last element is reversed when the hash-references
#		are pushed to the @DisconnectedEndpoints array as the
#		data-dumper output shows below
#
# Here's a data dump of the @ossi_output array data elements.
# @ossi_output Array data element looks like: 
# $VAR1 = {
#           '0002ff00' => '2001',
#           '0003ff00' => 'S00002',
#           '0001ff00' => '9640',
#           '0004ff00' => 'out-of-service'
#         };


# @ossi_output Array data element looks like: 
# $VAR1 = {
#           '0004ff00' => 'out-of-service',
#           '0003ff00' => 'S00005',
#           '0001ff00' => '9640',
#           '0002ff00' => '2002'
#         };



# ossi_output Array data element looks like: 
# $VAR1 = {
#           '0002ff00' => '2004',
#           '0001ff00' => '9641SIP',
#           '0003ff00' => 'S00007',
#           '0004ff00' => 'out-of-service'
#         };

#############################################################
# Here's the output of the @DisconnectedEndpoints after the push
#
# After push (should contain 1 element): 
# $VAR1 = 'out-of-service';
# $VAR2 = '2001';
# $VAR3 = 'S00002';
# $VAR4 = '9640';

# After push (should contain 1 element): 
# $VAR1 = 'S00005';
# $VAR2 = '2002';
# $VAR3 = '9640';
# $VAR4 = 'out-of-service';
#
# After push (should contain 1 element): 
# $VAR1 = '9641SIP';
# $VAR2 = '2004';
# $VAR3 = 'S00007';
# $VAR4 = 'out-of-service';
#
#
###########################################################


my $pbx = 'micklabs'; #'ojs'; #'rvs'; #'ouc2'; #'ouc1';#'pscc';'hsema'

my $debug ='';


my $help =0;
my $node;
my $phone;
my $output;
my $printout;

###########################################################
#
# 	OSSI Feild identifiers
#	
#	status-station FIDs
#-------------------------------------------------
# 	0002ff00 = Extension
#	0001ff00 = Programmed Station Type
#	0004ff00 = Service State 
#	6a02ff00 = Connected Set Type
#	6e00ff00 = MAC Address
#	0003ff00 = Port 
#
#	list stations FIDs
#-------------------------------------------------
#	8005ff00 = Extension
#	004fff00 = Station Type
#
#	display stations FIDs
#-------------------------------------------------
#
#	8007ff00 = Coverage Path
#	801f063d = Voicemail Button
#
my $PBXStatusStation_Extension = 		'0002ff00';
my $PBXStatusStation_ProgrammedType = 	'0001ff00';
my $PBXStatusStation_ConnectedType = 	'6a02ff00';
my $PBXStatusStation_MacAddress = 		'6e00ff00';
my $PBXStatusStation_ServiceState = 	'0004ff00';
my $PBXStatusStation_Port = 			'0003ff00';

my $PBXListStation_Extension 	= 		'8005ff00';
my $PBXListStation_StationType	= 		'004fff00';
my $PBXListStation_CoveragePath	= 		'004fff00';

my $PBXDisplayStation_CoveragePath = 	'8007ff00';
my $PBXDisplayStation_VoiceMailButton = '801f063d';


###########################################################


sub getDisconnectedEndpoints
{
	
	my @DisconnectedEndpoints = ();
    
		my ($node, $ext) = @_;

		my %FIDS = ($PBXStatusStation_Extension => '',$PBXStatusStation_ProgrammedType => '',$PBXStatusStation_ServiceState => '',$PBXStatusStation_Port => '');
	        $node->pbx_command("status station $ext", %FIDS );   
			if ($node->last_command_succeeded())

			{
				my @ossi_output = $node->get_ossi_objects();
				my ($hash_ref) = $ossi_output[0];	
						
					if ($hash_ref->{$PBXStatusStation_ServiceState} eq 'disconnected' or $hash_ref->{$PBXStatusStation_ServiceState} eq 'out-of-service')
					{
					
					#print $hash_ref->{$PBXStatusStation_Extension}.",".$hash_ref->{$PBXStatusStation_Port}.",".$hash_ref->{$PBXStatusStation_ProgrammedType}.",".$hash_ref->{$PBXStatusStation_ServiceState}."\n";
					push (@DisconnectedEndpoints, values $hash_ref);	
					print "After push (should contain 1 element): \n" . Dumper($hash_ref) . "\n";
					return @DisconnectedEndpoints;
					}
			return;
			}
	return 
} 


sub getListStations
{

	my($node) = @_;

	my @station;

	$node->pbx_command("list station");

	if ( $node->last_command_succeeded() ) {
		@station= $node->get_ossi_objects();
	}

	return @station;
}

$node = new cli_ossi($pbx, $debug);
unless( $node && $node->status_connection() ) {
   die("ERROR: Login failed for ". $node->get_node_name() );
}

foreach $phone (getListStations($node))
{
	
	#print $phone->{$PBXListStation_Extension}.",";
	print getDisconnectedEndpoints($node,$phone->{$PBXListStation_Extension});
	print "\n"	
		
}

$node->do_logoff();

