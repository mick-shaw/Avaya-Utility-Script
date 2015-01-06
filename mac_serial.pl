#!/usr/bin/perl -w
use strict;
###########################################################
#
# Author: Mick Shaw
# File: mac_serial.pl
# Company: Potomac Integration and Consulting
# Website: www.potomacintegration.com
# Date: 011/09/2015
#
# MAC Address, Serial Number and Firmware Report for Avaya
# IP Endpoints
#
# This script will run a list-registered command followed
# by a status station command using the output of the
# list-registered command. Finally, it will perform a
# snmpget using the SNMP_Session module.
#
#
# "$PBX" variable defines the CM instance. The connection
# details of each instance are defined in the OSSI
# Module (cli_ossi.pm).
#
# Note: If the $PBX variable changes, the OSSI Module must
# be updated as well
#
# Note: You may want to exclude CTI end-points.
# CTI endpoints typically show up as your AES
#	
#
#
###########################################################
###########################################################
# COMMUNICATION MANAGER API INTERFACE
# The cli_ossi module listed below is a modified version of
# Ben Roy's Definity.pm which is used to interface with
# Communication Manager via XML Interface.
# https://github.com/benroy73/pbxd/blob/master/pbx_lib/lib/PBX/DEFINITY.pm
require "/opt/AvayaOSSI/cli_ossi.pm";
import cli_ossi;
###########################################################
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
use lib '/opt/AvayaOSSI/SNMP_Session-1.13/lib';
use BER;
use SNMP_util;
use SNMP_Session;
#############################################################
use Getopt::Long;
use Pod::Usage;
use Net::Nslookup;
use Net::MAC;
#############################################################
# COMMUNICATION MANAGER CONNECTION
# The $pbx variable is defined in the cli_ossi.pm module
# which provides connection details for Aura Communication Manager
my $pbx = 'micklabs';
#############################################################
#############################################################
# SNMPSTRING
# The $snmp_ro variable needs to be set to the SNMPSTRING which
# is defined in the Avaya 46xxsettings.txt file
my $snmp_ro = 'avaya_ro';
#############################################################
# Intialize variables
my $debug ='';
my $help =0;
my $node;
my $voipphone;
my $MIB1;
my $MIB2;
my $value;
my $serialnumber;
my $phonefields;
###########################################################
#
# OSSI Feild identifiers
#
# status-station FIDs
#-------------------------------------------------
# 6a02ff00 = Station Type
# 6603ff00 = IP-Address of end-point
# 0004ff00 = Service State
# 6d00ff00 = Firmware Release
# 6e00ff00 = MAC Address
#
#
# list registered-ip-stations FIDs
#-------------------------------------------------
# 6800ff00 = Extension
# 6d00ff00 = Station Type
# 6d03ff00 = IP Address of Station
#
my $PBXgetPhoneMAC =  '6e00ff00';
my $PBXgetExtension = '6800ff00';
my $PBXgetSetType =   '6d00ff00';
my $PBXgetIPaddress = '6d03ff00';
###########################################################
sub getPhoneFields
{
my ($node, $ext) = @_;
my %fields = ('0001ff00' => '','6603ff00'=>'', '0004ff00' => '', '6a02ff00' => '', '6e00ff00' => '', '6d00ff00' => '');
$node->pbx_command("status station $ext", %fields );
if ($node->last_command_succeeded())
{
my @ossi_output = $node->get_ossi_objects();
my $hash_ref = $ossi_output[0];
print $hash_ref->{'0001ff00'}.",".$hash_ref->{'6603ff00'}.",".$hash_ref->{'0004ff00'}.",".$hash_ref->{'6a02ff00'}.",".$hash_ref->{'6e00ff00'}.",".$hash_ref->{'6d00ff00'}."\n";
return;
}
}
sub getserialnum {

my ($node) = @_;
$MIB1 = "1.3.6.1.4.1.6889.2.69.2.1.46.0";
$MIB2 = "1.3.6.1.4.1.6889.2.69.5.1.79.0";
($value) = &snmpget("$snmp_ro\@$node","$MIB2");
if ($value) { return "$value"; }
else{ ($value) = &snmpget("$snmp_ro\@$node","$MIB1");
if ($value) { return "$value"; }
else {
return "No response from host :$node"; }
return;
}}

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

$node = new cli_ossi($pbx, $debug);
unless( $node && $node->status_connection() ) {
die("ERROR: Login failed for ". $node->get_node_name() );
}
# Print out CSV column headers.
print "Extension,Serial Number,Programmed Set Type,IP Address,Service State,Connected Set Type,MAC Address,Firmware"."\n";
foreach $voipphone (getRegisteredPhones($node))
{
# Exclude any adresses - For example, I don't want the Avaya AES.
if ($voipphone->{$PBXgetIPaddress} !~ /^10\.88\.1\.36/)
{
$serialnumber = getserialnum($voipphone->{$PBXgetIPaddress});
print $voipphone->{$PBXgetExtension}.",";
print $serialnumber.",";
getPhoneFields($node,$voipphone->{$PBXgetExtension});
}
}
$node->do_logoff();
