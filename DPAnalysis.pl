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
# Author: Mick Shaw
# Company: Potomac Integration and Consulting
#
# Uniform-dialplan Report
#
# This script will provide a report of all stations
# in Communicaiton Manager and provide the current state
# of the station and where it's assigned in the uniform-dialplan
# table.  
#
# Too often the same extension is assigned to a station in multiple
# call-processors.  This report helps determine where the extension
# is being routed and if the station that's associated with the extension
# is in service.
#
#
# The "$pbx" variables defines the CM Instance to connect to
# The connection details for each CM Instance are defined in the
# OSSI Perl Module "cli_ossi.pm
#
# Note: If connection details for a given CM instance change (i.e. the
#       IP Adress changes) they must be changed in the cli_ossi perl module 
#
###########################################################


my $pbx = 'micklabs'; #'micklabs' #'ojs'; #'rvs'; #'ouc2'; #'ouc1';#'pscc';'hsema'


my $debug ='';

#$debug = 1;
my $help =0;
my $node;
my $voipphone;

###########################################################
#
# The Operations Support Systems Interface (OSSI)is a proprietary machine to machine data
# management facility that permits both retrieval and administration of all system management, maintenance
# and traffic information from AVAYA Communication Manager call-processors by providing form independent
# access to all SAT commands. When this machine interface to an OSS is combined with a flexible, user friendly interface
# inside the OSS, a powerful system administration tool is possible
#
# The following OSSI Field Identfiers are being used to generate the data for this report
#
#
############################################################

my $PBXgetPhoneMAC     = '6e00ff00';
my $PBXsetELIN         = '6e00ff00';
my $PBXgetELIN         = '6e00ff00';
my $PBXgetExtension    = '8005ff00'; 
my $PBXphonetype       = '0001ff00';
my $PBXphonestatus     = '0004ff00'; 
my $PBXmatchingpattern = '6c01ff01'; 
my $PBXmatchinglen     = '6c02ff01';

my $PBXpattern = '6c01ff00';
my $PBXinserts = '6c02ff00';

my %dialplans;

sub buildUniformDialplan
{
	my ($node) = @_;

	$node->pbx_command("list uniform-dialplan");
        if ( $node->last_command_succeeded() ) {
                my @ossi_output = $node->get_ossi_objects();
                foreach my $hash_ref(@ossi_output) {
			$hash_ref->{$PBXpattern} =~ s/\D+//g;
		 	$hash_ref->{$PBXinserts} =~ s/\D+//g;	
			$dialplans{$hash_ref->{$PBXpattern}} = $hash_ref->{$PBXinserts}; 
			#print ("dp ".$hash_ref->{$PBXpattern}." ".$hash_ref->{$PBXinserts}."\n");
                }
        }

}

sub getMatchingDialplan
{
	my ($ext) = @_;
	my $fullen = length($ext);

	$ext =~ s/\D+//g;


	while (length($ext) > 0)
	{
		if (exists($dialplans{$ext}))
			{
			print ",".$dialplans{$ext}.",";
			
			if ($fullen == length($ext))
			
			{
				print "fullmatch\n";
			}
			else
			{
				print "Partial Pattern Match ".$ext."\n";
			}
			return;
		}
		$ext = substr($ext, 0, -1);
		#print Dumper($ext);
	}

	print ",none,nomatch\n";
}

sub getPhoneFields
{

	my ($node, $ext) = @_;

	my %fields = ($PBXphonetype => '', $PBXphonestatus => '');

        $node->pbx_command("status station $ext", %fields );
        if ($node->last_command_succeeded())
	{
		my @ossi_output = $node->get_ossi_objects();
		my $hash_ref = $ossi_output[0];

		print $ext.",".$hash_ref->{$PBXphonetype}.",".$hash_ref->{$PBXphonestatus};

		getMatchingDialplan($ext);
		return;
	}
}




sub getRegisteredPhones
{
	# PBX : "You get to drink from the firehose!"
	my($node) = @_;
	my @registered;
	$node->pbx_command("list station");
	if ( $node->last_command_succeeded() ) {
		@registered= $node->get_ossi_objects();
	}
	return @registered;
}


GetOptions('help|?'=>\$help, 'debug' => \$debug,'pbx=s' =>\$pbx);
pod2usage(1) if $help;


$node = new cli_ossi($pbx, $debug);
unless( $node && $node->status_connection() ) {
   die("ERROR: Login failed for ". $node->get_node_name() );
}


buildUniformDialplan($node);

foreach $voipphone (getRegisteredPhones($node))
{
	#getPhoneFields($node,$voipphone->{$PBXgetExtension});	
	print $voipphone->{$PBXgetExtension};
	getMatchingDialplan($voipphone->{$PBXgetExtension});
}

$node->do_logoff();





__END__

=head1 NAME

testscript -- test script to show functionality

=head1 SYNOPSIS

testscript [options] 

=head1 OPTIONS

=item B<--pbx>

	Sets the pbx used to production or lab

=item B<--help | -?>

         prints this helpful message

=item B<--debug>

             helps with debugging

=cut
