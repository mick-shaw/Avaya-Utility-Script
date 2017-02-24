#!/usr/bin/perl -w
use strict;



##########################################################
# 			Aura Audit Utility 
#
# Author: Mick Shaw
# Company: Potomac Integration and Consulting
# Date: 01/06/2014
#
#
#	A collection of report tools that are used for gathering
#	information on Communication Manager instances
#
#
# "$PBX" variable defines the CM instance. The connection
#  details of each instance are defined in the OSSI
#  Module (cli_ossi.pm).
#
# Note: only values that have bee defined in the cli_ossi module 
#  can be used in the $PBX variable
#
###########################################################
# IP-Phone Report
#
# This report will run a list-registered command followed
# by a status station command using the output of the
# list-registered command.
#
#

#
# Note: 2420 Handsets registered as IP-Agents are excluded
#
#
###########################################################
# Disconnect Report
#
# This report will run a list station command followed
# by a status station using the output of the
# list station command
#

#
#
#
#
###########################################################
# Vector Messaging Report
# 
# This report will perform a list vector.  It will then
# perform a display vector and iterate accross all 99
# command steps.  if a message command is found it will
# write the coresponding messaging split/hunt-group and the
# corresponding extension associated with the messaging command
#
#
#
#
#
#
#
###########################################################
# SNMP LIBRARY
# The following modules should not be confused with the
#SNMP modues perl modules found in CPAN (i.e. Net::SNMP).
# These modules were previously maintained
# by http://www.switch.ch/misc/leinen/snmp/perl/ They are now
# publicly available on code.google.com/p/snmp-session
# The entire package which includes all three modules can be downloaded
# modules can be downloaded from
# https://snmp-session.googlecode.com/files/SNMP_Session-1.13.tar.gz
require "/opt/AvayaWebservice/cli_ossi.pm";
import cli_ossi;
use lib '/opt/AvayaWebservice/SNMP_Session-1.13/lib';
# Local library
use lib '/opt/AvayaWebservice/Otherlibs';

use BER;
use SNMP_util;
use SNMP_Session;
#############################################################
use Getopt::Long;
use Pod::Usage;
use Net::Nslookup;
use Net::MAC;
use Data::Dumper;
use Time::localtime;
use Mail::Send;
use MIME::Lite;


#
#############################################################
# SNMPSTRING
# The $snmp_ro variable needs to be set to the SNMPSTRING which
# is defined in the Avaya 46xxsettings.txt file
my $snmp_ro = 'avaya_ro';
#############################################################

my $pbx = 'micklabs'; #'ojs'; #'rvs'; #'ouc2'; #'ouc1';#'pscc';'hsema'

my $debug ='';


my $help =0;
my $node;
my $phone;
my $choice;
our $emailaddresses;
my $voipphone;
my $serialnumber;
my $PhoneFields;

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
#	list vector FIDs
#-------------------------------------------------
#   
#	0001ff01 = Vector number
#	
#
#
#
#
my $PBXStatusStation_Extension = 		'0002ff00';
my $PBXStatusStation_ProgrammedType = 	'0001ff00';
my $PBXStatusStation_ConnectedType = 	'6a02ff00';
my $PBXStatusStation_MacAddress = 		'6e00ff00';
my $PBXStatusStation_ServiceState = 	'0004ff00';
my $PBXStatusStation_Port = 			'0003ff00';
my $PBXStatusStation_IPAddress = 		'6603ff00';
my $PBXStatusStation_Firmware = 		'6d00ff00';

my $PBXListStation_Extension 	= 		'8005ff00';
my $PBXListStation_StationType	= 		'004fff00';
my $PBXListStation_CoveragePath	= 		'004fff00';

my $PBXListRegistered_IPAddress =		'6d03ff00';
my $PBXListRegistered_Extension =		'6800ff00';

my $PBXDisplayStation_CoveragePath = 	'8007ff00';
my $PBXDisplayStation_VoiceMailButton = '801f063d';

my $PBXListVector_VectorNumber = 		'0001ff01';

my $PBXDisplayVector_FIDSuffix;
my $PBXDisplayVector_CommandFID;
my $PBXDisplayVector_Command_ObjectFID;
my $PBXDisplayVector_Command_QualifierFID;
my $vectors;

my $Temp_FIDSuffix = 0x01;
my $VectorCounter01 = 0;
my $VectorCounter02 = 0;

my $AvayaOIDSN_01 = "1.3.6.1.4.1.6889.2.69.2.1.46.0";
my $AvayaOIDSN_02 = "1.3.6.1.4.1.6889.2.69.5.1.79.0";
my $Object_Value;

our $DisconnectReport = '' . timestamp() . '-' . $pbx . '-DisconnectReport.csv';
our $IPEndpointReport = '' . timestamp() . '-' . $pbx . '-IPEndpointReport.csv';
our $MsgVectorReport = '' . timestamp() . '-' . $pbx . '-MsgVectorReport.csv';

my $data;
my $msg;

our %CMD_FN_MAP =(
MENU_MAIN => \&MENU_MAIN, #
REPORT_MAIN => \&REPORT_MAIN, #
MENU_DISC_OPT => \&MENU_DISC_OPT, #
MENU_IPENDPT_OPT => \&MENU_IPENDPT_OPT, #
MENU_MSGVCTR_OPT => \&MENU_MSGVCTR_OPT, #

MENU_IPENDPT_WITHSNMP_OPT => \&MENU_IPENDPT_WITHSNMP_OPT, #
MENU_IPENDPT_WITHOUTSNMP_OPT=> \&MENU_IPENDPT_WITHOUTSNMP_OPT, #

RUN_DISC_REPORT => \&FN_RUN_DISC_REPORT, #


RUN_IPENDPT_WITHSNMP_REPORT => \&FN_RUN_IPENDPT_WITHSNMP_REPORT, #
RUN_IPENDPT_WITHOUTSNMP_REPORT => \&FN_RUN_IPENDPT_WITHOUTSNMP_REPORT, #

RUN_MSGVCTR_REPORT => \&FN_RUN_MSGVCTR_REPORT, #
);

###########################################################


sub timestamp {
  my $t = localtime;
  return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year + 1900, $t->mon + 1, $t->mday,
                  $t->hour, $t->min, $t->sec );
}

sub sendAttachment
{
   my( $from, $to, $subject, $filename, $data ) = @_;


$msg = MIME::Lite->new(
                 From     => $from,
                 To       => $to,
                 Subject  => $subject,
                 Type     => 'multipart/mixed'
                 );
                 
# Add your text message.
$msg->attach(Type         => 'text',
             Data         => $data 
            );
            
# Specify your file as attachement.
$msg->attach(Encoding 	 => '8bit',
			 Type        => 'text/csv', 
             Path        => './' . $filename,
             Filename    => $filename,
             Disposition => 'attachment'
            );       
$msg->send;
}

sub getVectorFields
{
	my @MessageVectors = ();
	my $Single_MessageVectors;

	my ($node, $vectornumber) =@_;
	my %fields =();


	while ($VectorCounter01 < 99)
	{

	$PBXDisplayVector_FIDSuffix 	= sprintf ("%02x", $Temp_FIDSuffix++);
	$PBXDisplayVector_CommandFID 	=  "0006ff".$PBXDisplayVector_FIDSuffix;
	$PBXDisplayVector_Command_ObjectFID 	=  "0023ff".$PBXDisplayVector_FIDSuffix;
	$PBXDisplayVector_Command_QualifierFID =  "0024ff".$PBXDisplayVector_FIDSuffix;

	$fields {$PBXDisplayVector_CommandFID} = '';
	$fields {$PBXDisplayVector_Command_ObjectFID} = '';
	$fields {$PBXDisplayVector_Command_QualifierFID} = '';
	$VectorCounter01++;
	
	}	
	$node->pbx_command("display vector $vectornumber", %fields );
        if ($node->last_command_succeeded())
	{
	my @ossi_output = $node->get_ossi_objects();
	my $hash_ref = $ossi_output[0];	
	
        $Temp_FIDSuffix = 0x01;	
	$VectorCounter02 = 0;
	while ($VectorCounter02 < 99)
	{
        	
	 $PBXDisplayVector_FIDSuffix = sprintf ("%02x", $Temp_FIDSuffix++);
        $PBXDisplayVector_CommandFID =  "0006ff".$PBXDisplayVector_FIDSuffix;
		#print Dumper ($hash_ref->{$PBXDisplayVector_CommandFID});
		if (defined $hash_ref->{$PBXDisplayVector_CommandFID})
		{
			if ($hash_ref->{$PBXDisplayVector_CommandFID} eq 'messaging')
			{
	$PBXDisplayVector_Command_ObjectFID =  "0023ff".$PBXDisplayVector_FIDSuffix;
	$PBXDisplayVector_Command_QualifierFID =  "0024ff".$PBXDisplayVector_FIDSuffix;		
	
	$Single_MessageVectors = ($vectornumber.",". $hash_ref->{$PBXDisplayVector_Command_ObjectFID}."," . $hash_ref->{$PBXDisplayVector_Command_QualifierFID} . "\n");
	push (@MessageVectors, $Single_MessageVectors);
	#print $vectornumber.",". $hash_ref->{$PBXDisplayVector_Command_ObjectFID}."," . $hash_ref->{$PBXDisplayVector_Command_QualifierFID} . "\n";

			}
		}	
       	$VectorCounter02++;
	}

	
	 
	}return @MessageVectors;

}

sub getListVectors
{

        my($node) = @_;

        my @vector;

        $node->pbx_command("list vector");

        if ( $node->last_command_succeeded() ) {
                @vector= $node->get_ossi_objects();
        }
	
        return @vector;
}

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
			}return @DisconnectedEndpoints;
	
} 

sub getPhoneFields
{
	
	my $Single_IPEndpoint;

	my ($node, $ext) = @_;
	my %FIDS = ($PBXStatusStation_ProgrammedType => '',$PBXStatusStation_IPAddress =>'', $PBXStatusStation_ServiceState => '', $PBXStatusStation_ConnectedType => '', $PBXStatusStation_MacAddress => '', $PBXStatusStation_Firmware => '');
	
	$node->pbx_command("status station $ext", %FIDS );
		
		if ($node->last_command_succeeded())
	
			{
	
				my @ossi_output = $node->get_ossi_objects();
				my $hash_ref = $ossi_output[0];
				
				$Single_IPEndpoint = ($hash_ref->{$PBXStatusStation_ProgrammedType}.",".$hash_ref->{$PBXStatusStation_IPAddress}.",".$hash_ref->{$PBXStatusStation_ServiceState}.",".$hash_ref->{$PBXStatusStation_ConnectedType}.",".$hash_ref->{$PBXStatusStation_MacAddress}.",".$hash_ref->{$PBXStatusStation_Firmware}."\n");
			} 
			return $Single_IPEndpoint;	
	

}

sub getserialnum {
	
	my ($node) = @_;
	
	($Object_Value) = &snmpget("$snmp_ro\@$node","$AvayaOIDSN_02");
	
	if ($Object_Value) { 

		return "$Object_Value"; }
		
		else{ ($Object_Value) = &snmpget("$snmp_ro\@$node","$AvayaOIDSN_01");
			
			if ($Object_Value) {

				 return "$Object_Value"; }

				else {

					return "No response from host :$node"; }

		return;
	}
}

sub getRegisteredPhones
{
	my($node) = @_;
	my @registered;
	
	$node->pbx_command("list registered");
		if ( $node->last_command_succeeded() ) {
		
		@registered= $node->get_ossi_objects();
		
	}
	
	return @registered;
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

sub runIPEndPointReport_with_SNMP
{

$node = new cli_ossi($pbx, $debug);
	unless( $node && $node->status_connection() ) {
		die("ERROR: Login failed for ". $node->get_node_name() );
	}
	# Print out CSV column headers.
	open(my $fh, '>', $IPEndpointReport) or die "Could not open file '$IPEndpointReport' $!";

	print $fh "Extension,Serial Number,Programmed Set Type,IP Address,Service State,Connected Set Type,MAC Address,Firmware"."\n";
	print 	  "Extension,Serial Number,Programmed Set Type,IP Address,Service State,Connected Set Type,MAC Address,Firmware"."\n";
	
	
	foreach $voipphone (getRegisteredPhones($node))
	{
		# Exclude any addresses - For example, I don't want the Avaya AES.
			if ($voipphone->{$PBXListRegistered_IPAddress} !~ /^10\.88\.1\.36/)
			{
				$serialnumber = getserialnum($voipphone->{$PBXListRegistered_IPAddress});
				$PhoneFields =getPhoneFields($node,$voipphone->{$PBXListRegistered_Extension});

				print $fh $voipphone->{$PBXListRegistered_Extension}.",";
				print $fh $serialnumber.",";
				print $fh $PhoneFields;
				print $voipphone->{$PBXListRegistered_Extension}.",";
				print $serialnumber.",";
				print $PhoneFields;

			}
	}
close	$fh;
$node->do_logoff();

}

sub runIPEndPointReport_without_SNMP
{

$node = new cli_ossi($pbx, $debug);
	unless( $node && $node->status_connection() ) {
		die("ERROR: Login failed for ". $node->get_node_name() );
	}
	# Print out CSV column headers.
	open(my $fh, '>', $IPEndpointReport) or die "Could not open file '$IPEndpointReport' $!";

	print $fh "Extension,Programmed Set Type,IP Address,Service State,Connected Set Type,MAC Address,Firmware"."\n";
	print 	  "Extension,Programmed Set Type,IP Address,Service State,Connected Set Type,MAC Address,Firmware"."\n";
	
	
	foreach $voipphone (getRegisteredPhones($node))
	{
		# Exclude any adresses - For example, I don't want the Avaya AES.
			if ($voipphone->{$PBXListRegistered_IPAddress} !~ /^10\.88\.1\.36/)
			{
				
				$PhoneFields =getPhoneFields($node,$voipphone->{$PBXListRegistered_Extension});

				print $fh $voipphone->{$PBXListRegistered_Extension}.",";
				print $fh $PhoneFields;
				print $voipphone->{$PBXListRegistered_Extension}.",";
				print $PhoneFields;

			}
	}
close	$fh;
$node->do_logoff();

}

sub runDisconnectReport
{
	$node = new cli_ossi($pbx, $debug);
	unless( $node && $node->status_connection() ) {
	   die("ERROR: Login failed for ". $node->get_node_name() );
		}
		open(my $fh, '>', $DisconnectReport) or die "Could not open file '$DisconnectReport' $!";

		print $fh "Extension, Port, Station-Type, Service-State\n";
		print 	  "Extension, Port, Station-Type, Service-State\n";	
		foreach $phone (getListStations($node))
		{
			print $fh getDisconnectedEndpoints($node,$phone->{$PBXListStation_Extension});	
			print getDisconnectedEndpoints($node,$phone->{$PBXListStation_Extension});	
				
		}
	close	$fh;
	$node->do_logoff();

}

sub runMessageVectorReport
{
	$node = new cli_ossi($pbx, $debug);
	unless( $node && $node->status_connection() ) {
	   die("ERROR: Login failed for ". $node->get_node_name() );
		}
		open(my $fh, '>', $MsgVectorReport) or die "Could not open file '$MsgVectorReport' $!";

		print $fh "Vector, Messaging HuntGroup, Extension\n";
		print 	  "Vector, Messaging HuntGroup, Extension\n";	
		foreach $vectors (getListVectors($node))
		{
			print $fh getVectorFields($node,$vectors->{$PBXListVector_VectorNumber});	
			print getVectorFields($node,$vectors->{$PBXListVector_VectorNumber});	
				
		}
	close	$fh;
	$node->do_logoff();

}
sub MENU_MAIN {
	print "\n\n";
	print "    ************************************\n";
	print "    *	  Aura Audit Report Menu       *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "    1. OJS\n";
	print "    2. Reeves\n";
	print "    3. OUC2\n";
	print "    4. Mick Lab\n\n";
	
	print 'Select The switch to query: ';
	chomp($choice = <STDIN>);
	if ($choice == 1){
		$pbx = 'ojs';
		return 'REPORT_MAIN';
	}
		elsif ($choice == 2) {
			$pbx = 'rvs';
			return 'REPORT_MAIN';
		} elsif ($choice == 3) {
			$pbx = 'ouc2';
			return 'REPORT_MAIN';
		} else {
			$pbx = 'micklabs';
			return 'REPORT_MAIN';
	}

	
	return 'REPORT_MAIN';
}

sub REPORT_MAIN {

our $DisconnectReport = '' . timestamp() . '-' . $pbx . '-DisconnectReport.csv';
our $IPEndpointReport = '' . timestamp() . '-' . $pbx . '-IPEndpointReport.csv';
our $MsgVectorReport = '' . timestamp() . '-' . $pbx . '-MsgVectorReport.csv';

	print "\n\n";
	print "    ************************************\n";
	print "    *	  Aura Audit Report Menu       *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "    1. Disconnect Report\n";
	print "    2. IP-Endpoint Report\n";
	print "    3. Message Vector Report\n\n";

	print 'Select your Activity: ';
	chomp($choice = <STDIN>);
	if ($choice == 1){
		return 'MENU_DISC_OPT';
	}
		elsif ($choice == 2) {
			return 'MENU_IPENDPT_OPT';
		} elsif ($choice == 3) {
			return 'MENU_MSGVCTR_OPT';
		} else {
			return 'REPORT_MAIN';
	}
	return 'REPORT_MAIN';
}

sub MENU_MSGVCTR_OPT {
	print "\n\n";
	print "    *************************************\n";
	print "    *    Message Vector Report Menu     *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "Enter an Email address to send the report: ";
	chomp($emailaddresses = <STDIN>);
	print '
	The report will be sent to: ';
	print "[" . $emailaddresses . ']';
	print "\n\nAre the addresses above correct? (y/n):";
	chomp($choice = <STDIN>);

	if ($choice eq 'y'){
		return 'RUN_MSGVCTR_REPORT';
	}
		elsif ($choice eq 'n') {
			return 'RUN_MSGVCTR_REPORT';
		} else {
			return 'REPORT_MAIN';
	}
	return 'REPORT_MAIN';
}

	


sub MENU_DISC_OPT {
	print "\n\n";
	print "    *************************************\n";
	print "    *	  Disconnect Report Menu       *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "Enter an Email address to send the report: ";
	chomp($emailaddresses = <STDIN>);
	print '
	The report will be sent to: ';
	print "[" . $emailaddresses . ']';
	print "\n\nAre the addresses above correct? (y/n):";
	chomp($choice = <STDIN>);
	if ($choice eq 'y'){
		return 'RUN_DISC_REPORT';
	}
		elsif ($choice eq 'n') {
			return 'MENU_DISC_OPT';
		} else {
			return 'REPORT_MAIN';
	}
	return 'REPORT_MAIN';
}

sub MENU_IPENDPT_OPT {
	print "\n\n";
	print "    *************************************\n";
	print "    *	  IP-Endpoint Report Menu      *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "\n\nDo you want to gather SNMP data? (y/n):";
	chomp($choice = <STDIN>);
	
	if ($choice eq 'y'){
		return 'MENU_IPENDPT_WITHSNMP_OPT';
	}
		elsif ($choice eq 'n') {
			return 'MENU_IPENDPT_WITHOUTSNMP_OPT';
		} else {
			return 'REPORT_MAIN';
	}
	return 'REPORT_MAIN';	

}

sub MENU_IPENDPT_WITHSNMP_OPT {
	print "\n\n";
	print "    ************************************\n";
	print "    *	  IP-Endpoint Report Menu      *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "Enter an Email address to send the report: ";
	chomp($emailaddresses = <STDIN>);
	print '
	The report will be sent to: ';
	print "[" . $emailaddresses . ']';
	print "\n\nAre the addresses above correct? (y/n):";
	chomp($choice = <STDIN>);
	if ($choice eq 'y'){
		return 'RUN_IPENDPT_WITHSNMP_REPORT';
	}
		elsif ($choice eq 'n') {
			return 'MENU_IPENDPT_OPT';
		} else {
			return 'REPORT_MAIN';
	}
	return 'REPORT_MAIN';	
	
}

sub MENU_IPENDPT_WITHOUTSNMP_OPT {
	print "\n\n";
	print "    ************************************\n";
	print "    *	  IP-Endpoint Report Menu      *\n";
	print "    *	                               *\n";
	print "    *	                               *\n";
	
	print "    ************************************\n";
	print "\n\n";
	print "Enter an Email address to send the report: ";
	chomp($emailaddresses = <STDIN>);
	print '
	The report will be sent to: ';
	print "[" . $emailaddresses . ']';
	print "\n\nAre the addresses above correct? (y/n):";
	chomp($choice = <STDIN>);
	if ($choice eq 'y'){
		return 'RUN_IPENDPT_WITHOUTSNMP_REPORT';
	}
		elsif ($choice eq 'n') {
			return 'MENU_IPENDPT_OPT';
		} else {
			return 'MENU_MAIN';
	}
	return 'MENU_MAIN';	
	

}

sub FN_RUN_MSGVCTR_REPORT
{
	print "\nYour Message Vector report is running \n\n";
	runMessageVectorReport();
	sendAttachment(
	    'AuraAudits@dc.gov>',
	    $emailaddresses,
	    'Message Vector Report',
	    $MsgVectorReport,
	    'Your Message Vector Report for ' . $pbx .  'is attached

	    ',
	);
	print "\n\nReport "."[".$MsgVectorReport."]"." is complete!\n\n"; 
	return '';
}

sub FN_RUN_DISC_REPORT
{
	print "\nYour Disconnect report for $pbx is running \n\n";
	runDisconnectReport();
	sendAttachment(
	    'AuraAudits@dc.gov>',
	    $emailaddresses,
	    'Disconnect Report',
	    $DisconnectReport,
	    'Your Disconnect Report for ' . $pbx .  ' is attached

	    ',
	);
	print "\n\nReport "."[".$DisconnectReport."]"." is complete!\n\n"; 
	return '';
}

sub FN_RUN_IPENDPT_WITHSNMP_REPORT
{
	print "\n\nYour IP-Endpoint report for $pbx is running \n\n";

	

runIPEndPointReport_with_SNMP();
	sendAttachment(
	    'AuraAudits@dc.gov>',
	    $emailaddresses,
	    'IP-Endpoint Report',
	    $IPEndpointReport,
	    'Your IP-Endpoint Report for ' . $pbx .  ' is attached

	    ',
	    
	);
	print "\n\nReport "."[".$IPEndpointReport."]"." is complete!\n\n"; 
	return '';
}

sub FN_RUN_IPENDPT_WITHOUTSNMP_REPORT
{
	print "\n\nYour IP-Endpoint report for $pbx is running \n\n";

	

runIPEndPointReport_without_SNMP();
	sendAttachment(
	    'AuraAudits@dc.gov>',
	    $emailaddresses,
	    'IP-Endpoint Report',
	    $IPEndpointReport,
	    'Your IP-Endpoint Report for ' . $pbx .  ' is attached

	    ',
	    
	);
	print "\n\nReport "."[".$IPEndpointReport."]"." is complete!\n\n"; 
	return '';
}

 my $next = MENU_MAIN();
 	while (1)
 	{
 		exit if !$next;
 		die if !exists $CMD_FN_MAP{uc($next)};
 		$next = &{$CMD_FN_MAP{uc($next)}}();
 	} 
