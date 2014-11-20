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
# 11/18 Completed Disconnect Report routine
#	TODO:  Add menu and continue to build report options
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
my $choice;
my $emailaddresses;

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

our %CMD_FN_MAP =(
MENU_MAIN => \&MENU_MAIN, #

MENU_DISC_OPT => \&MENU_DISC_OPT, #
MENU_IPENDPT_OPT => \&MENU_IPENDPT_OPT, #

RUN_DISC_REPORT => \&FN_RUN_DISC_REPORT, #
RUN_IPENDPT_REPORT => \&FN_RUN_IPENDPT_REPORT, #
);

###########################################################


sub getDisconnectedEndpoints
{
	
	my @DisconnectedEndpoints = ();
	my $Single_DisconnectedEndpoint;
    
    my ($node, $ext) = @_;

		my %FIDS = ($PBXStatusStation_Extension => '',$PBXStatusStation_Port => '',$PBXStatusStation_ProgrammedType => '',$PBXStatusStation_ServiceState => '');
	        $node->pbx_command("status station $ext", %FIDS );   
			if ($node->last_command_succeeded())

			{
				my @ossi_output = $node->get_ossi_objects();
			
				my ($hash_ref) = $ossi_output[0];	
						
					if ($hash_ref->{$PBXStatusStation_ServiceState} eq 'disconnected' or $hash_ref->{$PBXStatusStation_ServiceState} eq 'out-of-service')
					{
										
					$Single_DisconnectedEndpoint = ($hash_ref->{$PBXStatusStation_Extension}.",".$hash_ref->{$PBXStatusStation_Port}.",".$hash_ref->{$PBXStatusStation_ProgrammedType}.",".$hash_ref->{$PBXStatusStation_ServiceState}."\n");
					push (@DisconnectedEndpoints, $Single_DisconnectedEndpoint);
					
					}
			}
	
	return @DisconnectedEndpoints;

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

sub runDisconnectReport
{
$node = new cli_ossi($pbx, $debug);
unless( $node && $node->status_connection() ) {
   die("ERROR: Login failed for ". $node->get_node_name() );
}
print "Extension, Port, Station-Type, Service-State\n";

foreach $phone (getListStations($node))
{
	
	print getDisconnectedEndpoints($node,$phone->{$PBXListStation_Extension});	
		
}

$node->do_logoff();

}

sub MENU_MAIN {
print "\n Aura Audit Report Menu \n";
print "1. Disconnect Report\n";
print "2. IP-Endpoint Report\n";
print 'Your Audit Report choice ? ';
chomp($choice = <STDIN>);

return 'MENU_DISC_OPT' if $choice == 1;
return 'MENU_IPENDPT_OPT' if $choice == 2;
return '';
}

sub MENU_DISC_OPT {
print "\n Disconnect Report\n";
print 'Email addresses: ';
chomp($emailaddresses = <STDIN>);

return 'RUN_DISC_REPORT'
}

sub FN_RUN_DISC_REPORT
{
print "\nYour Disconnect report is running \n";
runDisconnectReport();
return '';
}

sub MENU_IPENDPT_OPT {
print "\n IP-Endpoint Report\n";
print 'Email addresses: ';
chomp($emailaddresses = <STDIN>);

return 'RUN_IPENDPT_REPORT'
}

sub FN_RUN_IPENDPT_REPORT
{
print "\nYour IP-Endpoint report is running \n";
return '';
}
my $next = MENU_MAIN();
while (1)
{
exit if !$next;
die if !exists $CMD_FN_MAP{uc($next)};
$next = &{$CMD_FN_MAP{uc($next)}}();
} 



