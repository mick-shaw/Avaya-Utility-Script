package cli_ossi;
# you'd probably prefer to read this documentation with perldoc

=head1 SYNOPSIS

cli_ossi.pm

=head1 DESCRIPTION

This module provided access to the ossi interface of an
Avaya Communication Manager telephone system (aka a Definity PBX).
Any PBX command available from the SAT terminal can be used.

The ossi interface is intended as a programmer's interface.
Interactive users should use the VT220 or 4410 terminal types instead.

Normally you will want to use the pbx_command method.
If you want formatted screen capture use the pbx_vt220_command method.

=head1 EXAMPLES

 BEGIN { require "./cli_ossi.pm"; import cli_ossi; }
 my $DEBUG = 1;
 my $node = new cli_ossi('n1', $DEBUG);
 unless( $node && $node->status_connection() ) {
 	die("ERROR: Login failed for ". $node->get_node_name() );
 }
 
 my %fields = ('0003ff00' => '');
 $node->pbx_command("display time", %fields );
 if ( $node->last_command_succeeded() ) {
 	my @ossi_output = $node->get_ossi_objects();
 	my $hash_ref = $ossi_output[0];
 	print "The PBX says the year is ". $hash_ref->{'0003ff00'} ."\n";
 }
 
 $node->pbx_command("status station 68258");
 if ( $node->last_command_succeeded() ) {
 	my @ossi_output = $node->get_ossi_objects();
 	my $i = 0;
 	foreach my $hash_ref(@ossi_output) {
 		$i++;
 		print "output result $i\n";
 		for my $field ( sort keys %$hash_ref ) {
 			my $value = $hash_ref->{$field};
 			print "\t$field => $value\n";
 		}
 	}
 }
 
 if ( $node->pbx_vt220_command('status logins') ) {
 	print $node->get_vt220_output();
 }
 
 $node->do_logoff();

=head1 AUTHOR

Benjamin Roy <benroy@uw.edu>

Copyright: May 2008
License: Apache 2.0

=cut back to the code, done with the POD text


use strict;
use Expect;
use Term::VT102;
use Data::Dumper;

$Expect::Debug         = 0;
$Expect::Exp_Internal  = 0;
$Expect::Log_Stdout    = 0;  #  STDOUT ...

use constant TERMTYPE  => "ossi4";  # options are ossi, ossi3, or ossi4
use constant TIMEOUT   => 60;

my $DEBUG = 0;

my $telnet_command = '/usr/bin/telnet';
my $ssh_command = '/usr/bin/ssh';
my $openssl_command = '/usr/bin/openssl s_client -quiet -connect';

# pbx_config contains the connection details for the PBX systems
# name   hostname   port   username    password    connection_type    atdt_number
my %pbx_config = (
  ouc2		   => [ 'ouc2',   '10.88.1.10',  '5022', 'webservice',  'Dragonf1r3',  'ssh', '' ],
  ojs		   => [ 'ojs',   '10.88.2.10',  '5022', 'webservice',  'Dragonf1r3',  'ssh', '' ],
  rvs	           => [ 'rvs', '10.88.0.10',  '5022', 'webservice',  'Dragonf1r3',  'ssh', '' ],
  ouc1	           => [ 'ouc1', '10.30.2.14', '5023','username', 'password', 'telnet', ''],
  pscc	           => [ 'pscc', '10.30.2.14', '5023','username', 'password', 'telnet', ''],
  hsema	           => [ 'hsema', '10.30.2.14', '5023','username', 'password', 'telnet', ''],
  dyrs	           => [ 'dyrs', '10.30.2.14', '5023','username', 'password', 'telnet', ''],
  micklabs         => [ 'micklabs', '192.168.1.210',  '5022', 'labs',  'Dragonf1r3',  'ssh', '' ],	
  sa09             => [ 'sa09', '10.192.32.10', '5022', 'labs', 'Dragonf1r3', 'ssh', '' ],
  voa              => [ 'voa', '192.11.13.6', '5022', 'brooks', 'brooks1', 'ssh', '' ],
);

#=============================================================
sub new {
#=============================================================
	my($class, @param) = @_;
	my $self = {};  # Create the anonymous hash reference to hold the object's data.
	bless $self, ref($class) || $class;

	if ($self->_initialize(@param)){
		return($self);
	} else {
		return(0);
	}
}

#=============================================================
sub _initialize {
#=============================================================
# my ($self, $nodename, $hostname, $port, $username, $password, $atdt, $debug_param) = @_;
# old programs need to be modified to use this new parameter order
#
	my ($self, $nodename, $debug_param) = @_;
	my ($hostname, $port, $username, $password, $connection_type, $atdt);

	if ( $debug_param ) {
		$DEBUG = $debug_param;
	}

	print "getting connection parameters for $nodename\n" if $DEBUG;

	if ( @{$pbx_config{$nodename}} ) {
		($nodename, $hostname, $port, $username, $password, $connection_type, $atdt) = @{$pbx_config{$nodename}};
		print "loaded $nodename config\n" if $DEBUG;
	}
	else {
		my $msg = "ERROR: unknown PBX [$nodename]. Config must be added to module before it can be used in production.";
		print "$msg\n";
		${$self->{'ERRORMSG'}} = "$msg";
		return(0);
	}

	${$self->{'NODENAME'}}  = $nodename;
	${$self->{'HOSTNAME'}}  = $hostname;
	${$self->{'PORT'}}      = $port;
	${$self->{'USERNAME'}}  = $username;
	${$self->{'PASSWORD'}}	= $password;
	${$self->{'ATDT'}}      = $atdt;
	${$self->{'CONNECTION_TYPE'}} = $connection_type;

	${$self->{'CONNECTED'}}	= 0;

	${$self->{'ERRORMSG'}}	= "";
	${$self->{'VT220_OUTPUT'}}	= "";
	@{$self->{'VT220_SCREENS'}}	= ();
	${$self->{'LAST_COMMAND_SUCCEEDED'}}	= 0;

	#  Array to hold generic ossi objects from a "list" command ...
	@{$self->{'OSSI_OBJECTS'}}	= ();

	#  Array to hold stations ...
	@{$self->{'STATIONS'}}	= ();

	#  Hash to hold uniform-dialplan by patterns...
	%{$self->{'UNIFORMDIALPLAN'}} = ();

	# Hash to hold extensions and type
	%{$self->{'EXTENSIONS'}}	= ();

	${$self->{'SESSION'}} = $self->init_session($hostname, $port, $username, $password, $connection_type, $atdt);

	return(1);
}

#=============================================================
sub init_session {
#=============================================================
	my ($self, $host, $port, $username, $password, $connection_type, $atdt) = @_;

	my $success = 0;

	my $s = new Expect;
	$s->raw_pty(1);
	$s->restart_timeout_upon_receive(1);

	my $command;
	if ( $connection_type eq 'telnet' ) {
		$command = "$telnet_command $host $port";
	}
	elsif ( $connection_type eq 'ssh' ) {
		$command = "$ssh_command -o \"StrictHostKeyChecking no\" -p $port -l $username $host";
	}
	elsif ( $connection_type eq 'ssl' ) {
		$command = "$openssl_command $host:$port";  #  Somehow the data module and telnet do not mix
	}
	else {
		my $msg = "ERROR: unhandled connection type requested. [$connection_type]";
		print "$msg\n" if $DEBUG;
		$self->{'ERRORMSG'} .= $msg;
		return(0);
	}

	print "$command\n" if $DEBUG;
	$s->spawn($command);

	if (defined($s)){
		$success = 0;
		$s->expect(TIMEOUT, 
			[ 'OK', sub {
				print "DEBUG Sending: 'ATDT $atdt'\n" if $DEBUG;
				my $self = shift;
				print $self "ATDT $atdt\n\r";
				exp_continue;
			} ],
			[ 'BUSY', sub {
				my $msg = "ERROR: The phone number was busy.";
				print "$msg\n" if $DEBUG;
				$self->{'ERRORMSG'} .= $msg;
			} ],
			[ 'Login resources unavailable', sub { 
				my $msg = "ERROR: No ports available.";
				print "$msg\n" if $DEBUG;
				$self->{'ERRORMSG'} .= $msg;
			}],
			[ '-re', '[Ll]ogin:|[Uu]sername:', sub {
				my $self = shift;
				print "Login: $username\n" if $DEBUG;
				print $self "$username\r";
				exp_continue;
			}],
			[ 'Password:', sub { 
				my $self = shift;
				print "entering password\n" if $DEBUG;
				print $self "$password\r";
				exp_continue;
			}],
			[ 'Terminal Type', sub { 
				my $self = shift;
				print "entering terminal type ".TERMTYPE."\n" if $DEBUG;
				print $self TERMTYPE . "\r";
				exp_continue;
			}],
			[ '-re', '^t$', sub { 
				print "connection established\n" if $DEBUG;
				$success = 1;
			}],
			[  eof => sub { 
				my $msg = "ERROR: Connection failed with EOF at login.";
				print "$msg\n" if $DEBUG;
				$self->{'ERRORMSG'} .= $msg;
			}],
			[  timeout => sub { 
				my $msg = "ERROR: Timeout on login.";
				print "$msg\n" if $DEBUG;
				$self->{'ERRORMSG'} .= $msg;
			}]
		);

		if (! $success) {
			return(0);
		}
		else {
			#  Verify command prompt ...
			sleep(1);
			print $s "\rt\r";
			$s->expect(TIMEOUT,
				[ '-re', 'Terminator received but no command active\nt\012'],
				[  eof => sub { 
					$success = 0;
					my $msg = "ERROR: Connection failed with EOF at verify command prompt.";
					print "$msg\n" if $DEBUG;
					$self->{'ERRORMSG'} .= $msg;
				}],
				[  timeout => sub { 
					$success = 0;
					my $msg = "ERROR: Timeout on verify command prompt.";
					print "$msg\n" if $DEBUG;
					$self->{'ERRORMSG'} .= $msg;
				}],
				[ '-re', '^t$', sub { 
					exp_continue;
				}]
			);
			if ($success) {
				$self->set_connected();
			} else {
				return(0);
			}
		}
	} else {
		my $msg = "ERROR: Could not create an Expect object.";
		print "$msg\n" if $DEBUG;
		$self->{'ERRORMSG'} .= $msg;
	}
	return($s);
}

#======================================================================
sub do_logoff {
#======================================================================
	my ($self) = @_;
	my $session = ${$self->{'SESSION'}};
	if ( $session ) {
		$session->send("c logoff \rt\r");
		$session->expect(TIMEOUT, 
							[ qr/NO CARRIER/i ],
							[ qr/Proceed With Logoff/i, sub { my $self = shift; $self->send("y\r"); } ],
							[ qr/onnection closed/i ] );
		$session->soft_close();
		print "PBX connection disconnected\n" if $DEBUG;
	}
	return(0); 
}


#======================================================================
#
# submit a command to the PBX and return the result
# fields can be specified to return only the fields desired
# data values for the fields can be included for "change" commands
#
# a good way to identify field id codes is to use a "display" command and 
# compare it to the output of the same command to a VT220 terminal
# for example to see all the fields for a change station you could call this
# function with a "display station" and no field list like this:
#  $node->pbx_command("display station");
#
sub pbx_command {
#======================================================================
	my ($self, $command, %fields) = @_;
	my $ossi_output = {};
	my $this = $self;
	my $session = ${$self->{'SESSION'}};
	my @field_ids;
	my @field_values;
	my $cmd_fields = "";
	my $cmd_values = "";
	my $command_succeeded = 1;
	$self->{'ERRORMSG'} = ''; #reset the error message
	@{$self->{'OSSI_OBJECTS'}} = (); #reset the objects array

	for my $field ( sort keys %fields ) {
		my $value = $fields{$field};
		$cmd_fields .= "$field\t";
		$cmd_values .= "$value\t";
	}
	chop $cmd_fields; # remove the trailing \t character
	chop $cmd_values;
	
	$session->send("c $command\r");
	print "DEBUG Sending \nc $command\n" if $DEBUG;
	if ( $cmd_fields ne '' ) {
		$session->send("f$cmd_fields\r");
		print "f$cmd_fields\n" if $DEBUG;
	}
	if ( $cmd_values ne '' ) {  # for a change command the data values for each field are entered here
		$session->send("d$cmd_values\r");
		print "d$cmd_values\n" if $DEBUG;
	}
	$session->send("t\r");
	print "t\n" if $DEBUG;

	$session->expect(TIMEOUT,
	[ '-re', '^f.*\x0a', sub {
		my $self = shift;
		my $a = trim( $self->match() );
		print "DEBUG Matched '$a'\n" if $DEBUG;
		$a =~ s/^f//;  # strip the leading 'f' off
		my ($field_1, $field_2, $field_3, $field_4, $field_5) = split(/\t/, $a, 5);
		#print "field_ids are: $field_1|$field_2|$field_3|$field_4|$field_5\n" if ($DEBUG);
		push(@field_ids, $field_1);
		push(@field_ids, $field_2);
		push(@field_ids, $field_3);
		push(@field_ids, $field_4);
		push(@field_ids, $field_5);
		exp_continue; 
	} ],
	[ '-re', '^[dent].*\x0a', sub {
		my $self = shift;
		my $a = trim( $self->match() );
		print "DEBUG Matched '$a'\n" if $DEBUG;

		if ( trim($a) eq "n" || trim($a) eq "t" ) { # end of record output
			# assign values to $ossi_output object
			for (my $i = 0; $i < scalar(@field_ids); $i++) {
				if ( $field_ids[$i] ) {
					$ossi_output->{$field_ids[$i]} = $field_values[$i];
				}
			}
			#	print Dumper($ossi_output) if $DEBUG;
			delete $ossi_output->{''}; # I'm not sure how this get's added but we don't want it.
			push(@{$this->{'OSSI_OBJECTS'}}, $ossi_output);
			@field_values = ();
			undef $ossi_output;
		}
		elsif ( substr($a,0,1) eq "d" ) { # field data line
			$a =~ s/^d//;  # strip the leading 'd' off
			my ($field_1, $field_2, $field_3, $field_4, $field_5) = split(/\t/, $a, 5);
			#	print "field_values are: $field_1|$field_2|$field_3|$field_4|$field_5\n" if ($DEBUG);
			push(@field_values, $field_1);
			push(@field_values, $field_2);
			push(@field_values, $field_3);
			push(@field_values, $field_4);
			push(@field_values, $field_5);
		}
		elsif ( substr($a,0,1) eq "e" ) { # error message line
			$a =~ s/^e//;  # strip the leading 'd' off
			my ($field_1, $field_2, $field_3, $field_4) = split(/ /, $a, 4);
			my $mess = $field_4;
			print "ERROR: field $field_2 $mess\n" if $DEBUG;
			$this->{'ERRORMSG'} .= "$field_2 $mess\n";
			$command_succeeded = 0;
		}
		else {
			print "ERROR: unknown match \"" . $self->match() ."\"\n";
		}

		unless ( trim($a) eq "t" ) {
			exp_continue;
		}
	} ],
	[  eof => sub {
		$command_succeeded = 0;
		my $msg = "ERROR: Connection failed with EOF in pbx_command($command).";
		print "$msg\n" if $DEBUG;
		$this->{'ERRORMSG'} .= $msg;
	} ],
	[  timeout => sub {
		$command_succeeded = 0;
		my $msg = "ERROR: Timeout in pbx_command($command).";
		print "$msg\n" if $DEBUG;
		$this->{'ERRORMSG'} .= $msg;
	} ],
	);
	
	if ( $command_succeeded ) {
		$this->{'LAST_COMMAND_SUCCEEDED'} = 1;
		return(1);
	}
	else {
		$this->{'LAST_COMMAND_SUCCEEDED'} = 0;
		return(0);
	}
}


#======================================================================
#
# capture the VT220 terminal screen output of a PBX command
#
sub pbx_vt220_command {
#======================================================================
	my ($self, $command) = @_;
	my $session = ${$self->{'SESSION'}};
	my $command_succeeded = 1;
	$self->{'ERRORMSG'} = ''; #reset the error message
	$self->{'VT220_OUTPUT'} = '';
	@{$self->{'VT220_SCREENS'}} = ();
	my $command_output = '';
	my $ESC         = chr(27);      #  \x1b
	my $CANCEL      = $ESC . "[3~";
	my $NEXT        = $ESC . "[6~"; 

#4410 keys
#F1=Cancel=<ESC>OP
#F2=Refresh=<ESC>OQ
#F3=Save=<ESC>OR
#F4=Clear=<ESC>OS
#F5=Help=<ESC>OT
#F6=GoTo=<ESC>Or  ...OR... F6=Update=<ESC>OX  ...or.... F6=Edit=<ESC>f6
#F7=NextPg=<ESC>OV
#F8=PrevPg=<ESC>OW

#VT220 keys
#Cancel          ESC[3~      F1
#Refresh         ESC[34~     F2
#Execute         ESC[29~     F3
#Clear Field     ESC[33~     F4
#Help            ESC[28~     F5
#Update Form     ESC[1~      F6
#Next Page       ESC[6~      F7
#Previous Page   ESC[5~      F8

	unless ( $self->status_connection() ) {
		$self->{'ERRORMSG'} .= 'ERROR: No connection to PBX.';
		$self->{'LAST_COMMAND_SUCCEEDED'} = 0;
		return(0);
	}
	
	# switch the terminal type from ossi to VT220
	$session->send("c newterm\rt\r");
	print "DEBUG switching to VT220 terminal type\n" if $DEBUG;

	$session->expect(TIMEOUT, 
		[ 'Terminal Type', sub { 
			$session->send("VT220\r");
			print "DEBUG sending VT220\n" if $DEBUG;
			exp_continue;
		}],
		[ '-re', 'Command:', sub { 
			print "DEBUG ready for next command.\n" if $DEBUG;
		}],
		[  timeout => sub { 
			my $msg = "ERROR: Timeout switching to VT220 terminal type.";
			print "$msg\n" if $DEBUG;
			$self->{'ERRORMSG'} .= $msg;
		}]
	);
	
	$session->send("$command\r");
	print "DEBUG Sending $command\n" if $DEBUG;

	$session->expect(TIMEOUT,
		[ '-re', '\x1b\[\d;\d\dH\x1b\[0m|\[KCommand:|press CANCEL to quit --  press NEXT PAGE to continue|Command successfully completed', sub {  # end of screen
#\[24;1H\x1b\[KCommand: 

			my $string = $session->before();
			$string =~ s/\x1b/\n/gm;
			print "DEBUG \$session->before()\n$string\n" if $DEBUG;
			
			#my $string = $session->before();
			#$string =~ s/\x1b/\n/gm;
			#print "Expect end of page\n$string\n";
			my $a = trim( $session->match() );
			print "DEBUG \$session->match() '$a'\n" if $DEBUG;
			my $current_page = 0;
			my $page_count = 1;
			if ( $session->before() =~ /Page +(\d*) of +(\d*)/ ) {
				$current_page = $1;
				$page_count = $2;
			}
			print "DEBUG on page $current_page out of $page_count pages\n" if $DEBUG;
			my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
			$vt->process( $session->before() );
			my $row = 0;
			my $screen;
			while ( $row < $vt->rows() ) {
				my $line = $vt->row_plaintext($row);
				$screen .= "$line\n" if $line;
				$row++;
			}
			print $screen if $DEBUG;
			push( @{$self->{'VT220_SCREENS'}}, $screen);
			$command_output .= $screen;
			if ( $session->match() eq 'Command successfully completed') {
				print "DEBUG \$session->match() is 'Command successfully completed'\n" if $DEBUG;
			}
			elsif ( $session->match() eq '[KCommand:') {
				print "DEBUG returned to 'Command:' prompt\n" if $DEBUG;
				if ( $session->after() ne ' ' ) {
					print "DEBUG \$session->after(): '". $session->after() ."'" if $DEBUG;

					my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
					$vt->process( $session->before() );
					my $msg = "ERROR: ". $vt->row_plaintext(23);
					print "$msg\n" if $DEBUG;
					$self->{'ERRORMSG'} .= $msg;

					$session->send("$CANCEL");
					$command_succeeded = 0;
				}
			}
			elsif ($current_page == $page_count) {
				print "DEBUG received last page. command finished\n" if $DEBUG;
				$session->send("$CANCEL");
			}
			elsif ($current_page < $page_count ) {
				print "DEBUG requesting next page\n" if $DEBUG;
				$session->send("$NEXT");
				exp_continue;
			}
			else {
				print "ERROR: unknown condition\n" if $DEBUG;
			}
		}],
		[  eof => sub {
			$command_succeeded = 0;
			my $msg = "ERROR: Connection failed with EOF in pbx_vt220_command($command).";
			print "$msg\n" if $DEBUG;
			$self->{'ERRORMSG'} .= $msg;
		} ],
		[  timeout => sub {
			$command_succeeded = 0;
			my $string = $session->before();
			$string =~ s/\x1b/\n/gm;
			print "ERROR: timeout in pbx_vt220_command($command)\n\$session->before()\n$string\n" if $DEBUG;

			my $vt = Term::VT102->new('cols' => 80, 'rows' => 24);
			$vt->process( $session->before() );
			my $msg = "ERROR: ". $vt->row_plaintext(23);
			print "$msg\n" if $DEBUG;
			$self->{'ERRORMSG'} .= $msg;

			$session->send("$CANCEL");
		} ],
	);

	# switch back to the original ossi terminal type
	print "DEBUG switching back to ossi terminal type\n" if $DEBUG;
	$session->send("$CANCEL");
	$session->send("newterm\r");
	print "DEBUG sending cancel and newterm\n" if $DEBUG;
	$session->expect(TIMEOUT, 
		[ 'Terminal Type', sub { 
			$session->send(TERMTYPE . "\r");
			print "DEBUG sending ". TERMTYPE ."\n" if $DEBUG;
			exp_continue;
		}],
		[ '-re', '^t$', sub { 
			print "DEBUG ready for next command\n" if $DEBUG;
		}],
		[  timeout => sub { 
			my $msg = "ERROR: Timeout while switching back to ossi terminal.";
			print "$msg\n" if $DEBUG;
			$self->{'ERRORMSG'} .= $msg;
		}]
	);

	if ( $command_succeeded ) {
		$self->{'LAST_COMMAND_SUCCEEDED'} = 1;
		$self->{'VT220_OUTPUT'} = $command_output;
		print "DEBUG command succeeded\n" if $DEBUG;
		return(1);
	}
	else {
		$self->{'LAST_COMMAND_SUCCEEDED'} = 0;
		print "DEBUG command failed\n" if $DEBUG;
		return(0);
	}

}




#======================================================================
sub list_uniform_dialplan {
		print "the list_uniform_dialplan() method is deprecated. use pbx_command() instead" if $DEBUG;
#======================================================================
	my ($self, $log) = @_;
	my $this = $self;
	my $session = ${$self->{'SESSION'}};
	$self->clear_uniform_dialplan();

#UNIFORM DIAL PLAN TABLE
#6c01ff00 = Matching Pattern
#ec36ff00 = Len
#ec37ff00 = Del
#6c02ff00 = Insert Digits
#6c03ff00 = Net
#6c04ff00 = Conv
#8fe0ff00 = Node Num
	my %field_params = (
			'6c01ff00' => '',
			'ec36ff00' => '',
			'ec37ff00' => '',
			'6c02ff00' => '',
			'6c03ff00' => '',
			'6c04ff00' => '',
			'8fe0ff00' => ''
		);
	$self->pbx_command("list uniform-dialplan", %field_params );
	if ( $self->last_command_succeeded() ) {
		my @ossi_output = $self->get_ossi_objects();

		foreach my $hash_ref ( @ossi_output ) {
			my $udp_pattern = $hash_ref->{'6c01ff00'};
			$this->{'UNIFORMDIALPLAN'}->{$udp_pattern} = $hash_ref;
		}
		return(0);
	}
	else {
		return(1);
	}
}

#======================================================================
sub list_stations {
	print "the list_stations() method is deprecated. use pbx_command() instead" if $DEBUG;
#======================================================================
	my ($self, $log) = @_;
	my $this = $self;
	my $session = ${$self->{'SESSION'}};
	$self->clear_stations();

	my %field_params = ( '8005ff00d' => '' );
	$self->pbx_command("list station", %field_params );

	if ( $self->last_command_succeeded() ) {
		my @ossi_output = $self->get_ossi_objects();
		foreach my $hash_ref ( @ossi_output ) {
			my $station = $hash_ref->{'8005ff00d'};
			push(@{$this->{'STATIONS'}}, $station);
		}
		return(0);
	}
	else {
		return(1);
	}
}


#======================================================================
sub list_extensions {
	print "the list_extensions() method is deprecated. use pbx_command() instead\n" if $DEBUG;
#======================================================================
	my ($self, $log) = @_;
	my $this = $self;
	my $session = ${$self->{'SESSION'}};
	my $extensions;

	my %field_params = ( '0001ff00' => '', '0002ff00' => '' );
	$self->pbx_command("list extension-type", %field_params );

	if ( $self->last_command_succeeded() ) {
		my @ossi_output = $self->get_ossi_objects();
		foreach my $hash_ref ( @ossi_output ) {
			my $ext = $hash_ref->{'0001ff00'};
			my $type = $hash_ref->{'0002ff00'};
			$extensions->{$ext} = $type;
		}
		$self->clear_extensions();
		$this->{'EXTENSIONS'} = $extensions;
		return(0);
	}
	else {
		return(1);
	}
}

#======================================================================
sub display_station_data {
	print "the display_station_data() method is deprecated. use pbx_command() instead\n" if $DEBUG;
#======================================================================
	my ($self, $station, $log, @fields) = @_;
	my $station_info;
	my $this = $self;
	my $session = ${$self->{'SESSION'}};
	my %field_params;

	foreach my $field (@fields) {
		$field_params{$field} = '';
	}

	$self->pbx_command("display station $station", %field_params );
	if ( $self->last_command_succeeded() ) {
		my @ossi_output = $self->get_ossi_objects();
		my $station_info = $ossi_output[0];
		return($station_info);
	}
	else {
		return(undef);
	}
}


#======================================================================
sub add_or_change_auth_code {  
	print "the add_or_change_auth_code() method is deprecated. use pbx_command() instead\n" if $DEBUG;
#======================================================================
	my ($self, $code, $cor, $log) = @_;
	
	my $command = "change authorization-code 9999999";
	if ( length($code) == 9 ) {
		$command = "change authorization-code 999999999";
	}
	
	my %field_params = ( '0001ff01' => $code, '802bff01' => $cor );
	$self->pbx_command( $command, %field_params );
	if ( $self->last_command_succeeded() ) {
		print $log "Ok\n";
		return(0);
	}
	else {
		print $log "Error: ". $self->get_last_error_message ."\n";
		return(1);
	}
}
#======================================================================
sub verify_code_installed {
	print "the verify_code_installed() method is deprecated. use pbx_command() instead\n" if $DEBUG;
#======================================================================
	my ($self, $code_in, $log) = @_;

	my %field_params = ( '0001ff00' => '' );
	$self->pbx_command( "list authorization-code start $code_in count 1", %field_params );

	if ( $self->last_command_succeeded() ) {
		my @ossi_output = $self->get_ossi_objects();
		my $hash_ref = $ossi_output[0];
		my $pbx_code = $hash_ref->{'0001ff00'};
		if ($pbx_code eq $code_in) { # the code is in the PBX
			return(1);
		}
		else {
			print $log "Error verify_code_installed(): code is not in the PBX.\n";
			return(0);
		}
	}
	else { # verification failed
		print $log "Error verify_code_installed(): ". $self->get_last_error_message ."\n";
		return(0);
	}
}
#======================================================================
sub delete_auth_code {
	print "the delete_auth_code() method is deprecated. use pbx_command() instead\n" if $DEBUG;
#======================================================================
	my ($self, $code, $log) = @_;

	#  Check if a code is actually installed before deleting (else the wrong code will be deleted) ...
	if ( ! $self->verify_code_installed($code, $log) ) {
		return(0);  #  This shouldn't be a fatal error
	}

	my %field_params = ( '0001ff01' => ' ', '802bff01' => ' ' );
	
	$self->pbx_command( "change authorization-code $code", %field_params);
	if ( $self->last_command_succeeded() ) {
		print $log "Ok\n";
		return(0);
	}
	else {
		print $log "Error: ". $self->get_last_error_message ."\n";
		return(1);
	}
}


#=============================================================
sub trim($)
#=============================================================
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

#=============================================================
sub get_extension_type {
#=============================================================
	my ($self, $extension) = @_;
	my %hash = %{$self->{'EXTENSIONS'}};
	my $type = $hash{$extension};
	return($type)
}

#=============================================================
sub get_extensions {
#=============================================================
	my ($self) = @_;
	return( sort {$a <=> $b} keys %{$self->{'EXTENSIONS'}} );
}

#=============================================================
sub get_stations {
#=============================================================
	my ($self) = @_;
	while ( my($key,$value) = each(%{$self->{'EXTENSIONS'}}) ) {
		if ($value eq "station-user") {
			push(@{$self->{'STATIONS'}}, $key);
		}
	}
	return( sort {$a <=> $b} @{$self->{'STATIONS'}} );
}

#=============================================================
sub get_uniform_dialplan {
#=============================================================
	my ($self) = @_;
	return( $self->{'UNIFORMDIALPLAN'} );
}

#=============================================================
sub clear_uniform_dialplan {
#=============================================================
	my ($self) = @_;
	%{$self->{'UNIFORMDIALPLAN'}} = ();
}

#=============================================================
sub clear_stations {
#=============================================================
	my ($self) = @_;
	@{$self->{'STATIONS'}} = ();
}

#=============================================================
sub clear_extensions {
#=============================================================
	my ($self) = @_;
	%{$self->{'EXTENSIONS'}} = ();
}

#=============================================================
sub get_last_error_message {
#=============================================================
	my ($self) = @_;
	return( $self->{'ERRORMSG'} );
}

#=============================================================
sub last_command_succeeded {
#=============================================================
	my ($self) = @_;
	return( $self->{'LAST_COMMAND_SUCCEEDED'} );
}

#=============================================================
sub get_ossi_objects {
#=============================================================
	my ($self) = @_;
	return( @{$self->{'OSSI_OBJECTS'}} );
}

#=============================================================
sub get_vt220_output {
#=============================================================
	my ($self) = @_;
	return($self->{'VT220_OUTPUT'});
}
#=============================================================
sub get_vt220_screens {
#=============================================================
	my ($self) = @_;
	return( @{$self->{'VT220_SCREENS'}} );
}

#=============================================================
sub get_node_name {
#=============================================================
	my ($self) = @_;
	return(${$self->{'NODENAME'}});
}

#=============================================================
sub set_connected {
#=============================================================
	my ($self) = @_;
	${$self->{'CONNECTED'}} = 1;
}

#=============================================================
sub unset_connected {
#=============================================================
	my ($self) = @_;
	${$self->{'CONNECTED'}} = 0;
}

#=============================================================
sub status_connection {
#=============================================================
	my ($self) = @_;
	return(${$self->{'CONNECTED'}});
}

1;
