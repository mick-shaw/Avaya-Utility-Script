#!/usr/bin/perl -w
use strict;

require "./cli_ossi.pm";
import cli_ossi;

use Getopt::Long;
use Pod::Usage;
use Net::Nslookup;
use Net::MAC;

###########################################################
#
# Author: Mick Shaw
# Company: Potomac Integration and Consulting
#
# Voice Mail Migration Report
#
# This script will read-in a csv file of a list of extensions
# it will then modify the coverage path of the list of extension
# 
#
#
#
#
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
	
	
	
    
	#my @DisconnectedEndpoints;
    
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
						#push (@DisconnectedEndpoints, $output);
					return  (\%FIDS);
					}
			return;
			}
	return #@DisconnectedEndpoints;
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
		
}

$node->do_logoff();

