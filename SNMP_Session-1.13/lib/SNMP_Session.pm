### -*- mode: Perl -*-
######################################################################
### SNMP Request/Response Handling
######################################################################
### Copyright (c) 1995-2008, Simon Leinen.
###
### This program is free software; you can redistribute it under the
### "Artistic License 2.0" included in this distribution
### (file "Artistic").
######################################################################
### The abstract class SNMP_Session defines objects that can be used
### to communicate with SNMP entities.  It has methods to send
### requests to and receive responses from an agent.
###
### Two instantiable subclasses are defined:
### SNMPv1_Session implements SNMPv1 (RFC 1157) functionality
### SNMPv2c_Session implements community-based SNMPv2.
######################################################################
### Created by:  Simon Leinen  <simon@switch.ch>
###
### Contributions and fixes by:
###
### Matthew Trunnell <matter@media.mit.edu>
### Tobias Oetiker <tobi@oetiker.ch>
### Heine Peters <peters@dkrz.de>
### Daniel L. Needles <dan_needles@INS.COM>
### Mike Mitchell <mcm@unx.sas.com>
### Clinton Wong <clintdw@netcom.com>
### Alan Nichols <Alan.Nichols@Ebay.Sun.COM>
### Mike McCauley <mikem@open.com.au>
### Andrew W. Elble <elble@icculus.nsg.nwu.edu>
### Brett T Warden <wardenb@eluminant.com>: pretty UInteger32
### Michael Deegan <michael@cnspc18.murdoch.edu.au>
### Sergio Macedo <macedo@tmp.com.br>
### Jakob Ilves (/IlvJa) <jakob.ilves@oracle.com>: PDU capture
### Valerio Bontempi <v.bontempi@inwind.it>: IPv6 support
### Lorenzo Colitti <lorenzo@colitti.com>: IPv6 support
### Philippe Simonet <Philippe.Simonet@swisscom.com>: Export avoid...
### Luc Pauwels <Luc.Pauwels@xalasys.com>: use_16bit_request_ids
### Andrew Cornford-Matheson <andrew.matheson@corenetworks.com>: inform
### Gerry Dalton <gerry.dalton@consolidated.com>: strict subs bug
### Mike Fischer <mlf2@tampabay.rr.com>: pass MSG_DONTWAIT to recv()
######################################################################

package SNMP_Session;		

require 5.002;

use strict;
use Exporter;
use vars qw(@ISA $VERSION @EXPORT $errmsg
	    $suppress_warnings
	    $default_avoid_negative_request_ids
	    $default_use_16bit_request_ids);
use Socket;
use BER '1.05';
use Carp;

sub map_table ($$$ );
sub map_table_4 ($$$$);
sub map_table_start_end ($$$$$$);
sub index_compare ($$);
sub oid_diff ($$);

$VERSION = '1.13';

@ISA = qw(Exporter);

@EXPORT = qw(errmsg suppress_warnings index_compare oid_diff recycle_socket ipv6available);

my $default_debug = 0;

### Default initial timeout (in seconds) waiting for a response PDU
### after a request is sent.  Note that when a request is retried, the
### timeout is increased by BACKOFF (see below).
###
my $default_timeout = 2.0;

### Default number of attempts to get a reply for an SNMP request.  If
### no response is received after TIMEOUT seconds, the request is
### resent and a new response awaited with a longer timeout (see the
### documentation on BACKOFF below).  The "retries" value should be at
### least 1, because the first attempt counts, too (the name "retries"
### is confusing, sorry for that).
###
my $default_retries = 5;

### Default backoff factor for SNMP_Session objects.  This factor is
### used to increase the TIMEOUT every time an SNMP request is
### retried.
###
my $default_backoff = 1.0;

### Default value for maxRepetitions.  This specifies how many table
### rows are requested in getBulk requests.  Used when walking tables
### using getBulk (only available in SNMPv2(c) and later).  If this is
### too small, then a table walk will need unnecessarily many
### request/response exchanges.  If it is too big, the agent may
### compute many variables after the end of the table.  It is
### recommended to set this explicitly for each table walk by using
### map_table_4().
###
my $default_max_repetitions = 12;

### Default value for "avoid_negative_request_ids".
###
### Set this to non-zero if you have agents that have trouble with
### negative request IDs, and don't forget to complain to your agent
### vendor.  According to the spec (RFC 1905), the request-id is an
### Integer32, i.e. its range is from -(2^31) to (2^31)-1.  However,
### some agents erroneously encode the response ID as an unsigned,
### which prevents this code from matching such responses to requests.
###
$SNMP_Session::default_avoid_negative_request_ids = 0;

### Default value for "use_16bit_request_ids".
###
### Set this to non-zero if you have agents that use 16bit request IDs,
### and don't forget to complain to your agent vendor.
###
$SNMP_Session::default_use_16bit_request_ids = 0;

### Whether all SNMP_Session objects should share a single UDP socket.
###
$SNMP_Session::recycle_socket = 0;

### IPv6 initialization code: check that IPv6 libraries are available,
### and if so load them.

### We store the length of an IPv6 socket address structure in the class
### so we can determine if a socket address is IPv4 or IPv6 just by checking
### its length. The proper way to do this would be to use sockaddr_family(),
### but this function is only available in recent versions of Socket.pm.
my $ipv6_addr_len;

### Flags to be passed to recv() when non-blocking behavior is
### desired.  On most POSIX-like systems this will be set to
### MSG_DONTWAIT, on other systems we leave it at zero.
###
my $dont_wait_flags;

BEGIN {
    $ipv6_addr_len = undef;
    $SNMP_Session::ipv6available = 0;
    $dont_wait_flags = 0;

    if (eval {local $SIG{__DIE__};require Socket6;} &&
       eval {local $SIG{__DIE__};require IO::Socket::INET6; IO::Socket::INET6->VERSION("1.26");}) {
        Socket6->import(qw(inet_pton getaddrinfo));
	# import Socket6;
	$ipv6_addr_len = length(pack_sockaddr_in6(161, inet_pton(AF_INET6(), "::1")));
	$SNMP_Session::ipv6available = 1;
    }
    eval 'local $SIG{__DIE__};local $SIG{__WARN__};$dont_wait_flags = MSG_DONTWAIT();';
}

### Cache for reusable sockets.  This is indexed by socket (address)
### family, so that we don't try to reuse an IPv4 socket for IPv6 or
### vice versa.
###
my %the_socket = ();

$SNMP_Session::errmsg = '';
$SNMP_Session::suppress_warnings = 2;

sub get_request      { 0 | context_flag () };
sub getnext_request  { 1 | context_flag () };
sub get_response     { 2 | context_flag () };
sub set_request      { 3 | context_flag () };
sub trap_request     { 4 | context_flag () };
sub getbulk_request  { 5 | context_flag () };
sub inform_request   { 6 | context_flag () };
sub trap2_request    { 7 | context_flag () };

sub standard_udp_port { 161 };

sub open
{
    return SNMPv1_Session::open (@_);
}

sub timeout { $_[0]->{timeout} }
sub retries { $_[0]->{retries} }
sub backoff { $_[0]->{backoff} }
sub set_timeout {
    my ($session, $timeout) = @_;
    croak ("timeout ($timeout) must be a positive number") unless $timeout > 0.0;
    $session->{'timeout'} = $timeout;
}
sub set_retries {
    my ($session, $retries) = @_;
    croak ("retries ($retries) must be a non-negative integer")
	unless $retries == int ($retries) && $retries >= 0;
    $session->{'retries'} = $retries; 
}
sub set_backoff {
    my ($session, $backoff) = @_;
    croak ("backoff ($backoff) must be a number >= 1.0")
	unless $backoff == int ($backoff) && $backoff >= 1.0;
    $session->{'backoff'} = $backoff; 
}

sub encode_request_3 ($$$@) {
    my($this, $reqtype, $encoded_oids_or_pairs, $i1, $i2) = @_;
    my($request);
    local($_);

    $this->{request_id} = ($this->{request_id} == 0x7fffffff)
	? -0x80000000 : $this->{request_id}+1;
    $this->{request_id} += 0x80000000
	if ($this->{avoid_negative_request_ids} && $this->{request_id} < 0);
    $this->{request_id} &= 0x0000ffff
	if ($this->{use_16bit_request_ids});
    foreach $_ (@{$encoded_oids_or_pairs}) {
      if (ref ($_) eq 'ARRAY') {
	$_ = &encode_sequence ($_->[0], $_->[1])
	  || return $this->ber_error ("encoding pair");
      } else {
	$_ = &encode_sequence ($_, encode_null())
	  || return $this->ber_error ("encoding value/null pair");
      }
    }
    $request = encode_tagged_sequence
	($reqtype,
	 encode_int ($this->{request_id}),
	 defined $i1 ? encode_int ($i1) : encode_int_0 (),
	 defined $i2 ? encode_int ($i2) : encode_int_0 (),
	 encode_sequence (@{$encoded_oids_or_pairs}))
	  || return $this->ber_error ("encoding request PDU");
    return $this->wrap_request ($request);
}

sub encode_get_request {
    my($this, @oids) = @_;
    return encode_request_3 ($this, get_request, \@oids);
}

sub encode_getnext_request {
    my($this, @oids) = @_;
    return encode_request_3 ($this, getnext_request, \@oids);
}

sub encode_getbulk_request {
    my($this, $non_repeaters, $max_repetitions, @oids) = @_;
    return encode_request_3 ($this, getbulk_request, \@oids,
			     $non_repeaters, $max_repetitions);
}

sub encode_set_request {
    my($this, @encoded_pairs) = @_;
    return encode_request_3 ($this, set_request, \@encoded_pairs);
}

sub encode_trap_request ($$$$$$@) {
    my($this, $ent, $agent, $gen, $spec, $dt, @pairs) = @_;
    my($request);
    local($_);

    foreach $_ (@pairs) {
      if (ref ($_) eq 'ARRAY') {
	$_ = &encode_sequence ($_->[0], $_->[1])
	  || return $this->ber_error ("encoding pair");
      } else {
	$_ = &encode_sequence ($_, encode_null())
	  || return $this->ber_error ("encoding value/null pair");
      }
    }
    $request = encode_tagged_sequence
	(trap_request, $ent, $agent, $gen, $spec, $dt, encode_sequence (@pairs))
	  || return $this->ber_error ("encoding trap PDU");
    return $this->wrap_request ($request);
}

sub encode_v2_trap_request ($@) {
    my($this, @pairs) = @_;

    return encode_request_3($this, trap2_request, \@pairs);
}

sub decode_get_response {
    my($this, $response) = @_;
    my @rest;
    @{$this->{'unwrapped'}};
}

sub decode_trap_request ($$) {
    my ($this, $trap) = @_;
    my ($snmp_version, $community, $ent, $agent, $gen, $spec, $dt,
	$request_id, $error_status, $error_index,
	$bindings);
    ($snmp_version, $community,
     $ent, $agent,
     $gen, $spec, $dt,
     $bindings)
	= decode_by_template ($trap, "%{%i%s%*{%O%A%i%i%u%{%@",
			    trap_request);
    if (!defined $snmp_version) {
	($snmp_version, $community,
	 $request_id, $error_status, $error_index,
	 $bindings)
	    = decode_by_template ($trap, "%{%i%s%*{%i%i%i%{%@",
				  trap2_request);
	if (!defined $snmp_version) {
	    ($snmp_version, $community,$request_id, $error_status, $error_index, $bindings)
		= decode_by_template ($trap, "%{%i%s%*{%i%i%i%{%@", inform_request);
	}
	return $this->error_return ("v2 trap/inform request contained errorStatus/errorIndex "
				    .$error_status."/".$error_index)
	    if defined $error_status && defined $error_index
	    && ($error_status != 0 || $error_index != 0);
    }
    if (!defined $snmp_version) {
	return $this->error_return ("BER error decoding trap:\n  ".$BER::errmsg);
    }
    return ($community, $ent, $agent, $gen, $spec, $dt, $bindings);
}

sub wait_for_response {
    my($this) = shift;
    my($timeout) = shift || 10.0;
    my($rin,$win,$ein) = ('','','');
    my($rout,$wout,$eout);
    vec($rin,$this->sockfileno,1) = 1;
    select($rout=$rin,$wout=$win,$eout=$ein,$timeout);
}

sub get_request_response ($@) {
    my($this, @oids) = @_;
    return $this->request_response_5 ($this->encode_get_request (@oids),
				      get_response, \@oids, 1);
}

sub set_request_response ($@) {
    my($this, @pairs) = @_;
    return $this->request_response_5 ($this->encode_set_request (@pairs),
				      get_response, \@pairs, 1);
}

sub getnext_request_response ($@) {
    my($this,@oids) = @_;
    return $this->request_response_5 ($this->encode_getnext_request (@oids),
				      get_response, \@oids, 1);
}

sub getbulk_request_response ($$$@) {
    my($this,$non_repeaters,$max_repetitions,@oids) = @_;
    return $this->request_response_5
	($this->encode_getbulk_request ($non_repeaters,$max_repetitions,@oids),
	 get_response, \@oids, 1);
}

sub trap_request_send ($$$$$$@) {
    my($this, $ent, $agent, $gen, $spec, $dt, @pairs) = @_;
    my($req);

    $req = $this->encode_trap_request ($ent, $agent, $gen, $spec, $dt, @pairs);
    ## Encoding may have returned an error.
    return undef unless defined $req;
    $this->send_query($req)
	|| return $this->error ("send_trap: $!");
    return 1;
}

sub v2_trap_request_send ($$$@) {
    my($this, $trap_oid, $dt, @pairs) = @_;
    my @sysUptime_OID = ( 1,3,6,1,2,1,1,3 );
    my @snmpTrapOID_OID = ( 1,3,6,1,6,3,1,1,4,1 );
    my($req);

    unshift @pairs, [encode_oid (@snmpTrapOID_OID,0),
		     encode_oid (@{$trap_oid})];
    unshift @pairs, [encode_oid (@sysUptime_OID,0),
		     encode_timeticks ($dt)];
    $req = $this->encode_v2_trap_request (@pairs);
    ## Encoding may have returned an error.
    return undef unless defined $req;
    $this->send_query($req)
	|| return $this->error ("send_trap: $!");
    return 1;
}

sub request_response_5 ($$$$$) {
    my ($this, $req, $response_tag, $oids, $errorp) = @_;
    my $retries = $this->retries;
    my $timeout = $this->timeout;
    my ($nfound, $timeleft);

    ## Encoding may have returned an error.
    return undef unless defined $req;

    $timeleft = $timeout;
    while ($retries > 0) {
	$this->send_query ($req)
	    || return $this->error ("send_query: $!");
	# IlvJa
	# Add request pdu to capture_buffer
	push @{$this->{'capture_buffer'}}, $req
	    if (defined $this->{'capture_buffer'}
		and ref $this->{'capture_buffer'} eq 'ARRAY');
	#
      wait_for_response:
	($nfound, $timeleft) = $this->wait_for_response($timeleft);
	if ($nfound > 0) {
	    my($response_length);

	    $response_length
		= $this->receive_response_3 ($response_tag, $oids, $errorp, 1);
	    if ($response_length) {
		# IlvJa
		# Add response pdu to capture_buffer
		push (@{$this->{'capture_buffer'}},
		      substr($this->{'pdu_buffer'}, 0, $response_length)
		      )
		      if (defined $this->{'capture_buffer'}
			  and ref $this->{'capture_buffer'} eq 'ARRAY');
		#
		return $response_length;
	    } elsif (defined ($response_length)) {
		goto wait_for_response;
		# A response has been received, but for a different
		# request ID or from a different IP address.
	    } else {
		return undef;
	    }
	} else {
	    ## No response received - retry
	    --$retries;
	    $timeout *= $this->backoff;
	    $timeleft = $timeout;
	}
    }
    # IlvJa
    # Add empty packet to capture_buffer
    push @{$this->{'capture_buffer'}}, "" 
	if (defined $this->{'capture_buffer'}
	    and ref $this->{'capture_buffer'} eq 'ARRAY');
    #
    $this->error ("no response received");
}

sub map_table ($$$) {
    my ($session, $columns, $mapfn) = @_;
    return $session->map_table_4 ($columns, $mapfn,
				  $session->default_max_repetitions ());
}

sub map_table_4 ($$$$) {
    my ($session, $columns, $mapfn, $max_repetitions) = @_;
    return $session->map_table_start_end ($columns, $mapfn,
					  "", undef,
					  $max_repetitions);
}

sub map_table_start_end ($$$$$$) {
    my ($session, $columns, $mapfn, $start, $end, $max_repetitions) = @_;

    my @encoded_oids;
    my $call_counter = 0;
    my $base_index = $start;

    do {
	foreach (@encoded_oids = @{$columns}) {
	    $_=encode_oid (@{$_},split '\.',$base_index)
		|| return $session->ber_error ("encoding OID $base_index");
	}
	if ($session->getnext_request_response (@encoded_oids)) {
	    my $response = $session->pdu_buffer;
	    my ($bindings) = $session->decode_get_response ($response);
	    my $smallest_index = undef;
	    my @collected_values = ();

	    my @bases = @{$columns};
	    while ($bindings ne '') {
		my ($binding, $oid, $value);
		my $base = shift @bases;
		($binding, $bindings) = decode_sequence ($bindings);
		($oid, $value) = decode_by_template ($binding, "%O%@");

		my $out_index;

		$out_index = &oid_diff ($base, $oid);
		my $cmp;
		if (!defined $smallest_index
		    || ($cmp = index_compare ($out_index,$smallest_index)) == -1) {
		    $smallest_index = $out_index;
		    grep ($_=undef, @collected_values);
		    push @collected_values, $value;
		} elsif ($cmp == 1) {
		    push @collected_values, undef;
		} else {
		    push @collected_values, $value;
		}
	    }
	    (++$call_counter,
	     &$mapfn ($smallest_index, @collected_values))
		if defined $smallest_index;
	    $base_index = $smallest_index;
	} else {
	    return undef;
	}
    }
    while (defined $base_index
	   && (!defined $end || index_compare ($base_index, $end) < 0));
    $call_counter;
}

sub index_compare ($$) {
  my ($i1, $i2) = @_;
  $i1 = '' unless defined $i1;
  $i2 = '' unless defined $i2;
  if ($i1 eq '') {
      return $i2 eq '' ? 0 : 1;
  } elsif ($i2 eq '') {
      return 1;
  } elsif (!$i1) {
      return $i2 eq '' ? 1 : !$i2 ? 0 : 1;
  } elsif (!$i2) {
      return -1;
  } else {
    my ($f1,$r1) = split('\.',$i1,2);
    my ($f2,$r2) = split('\.',$i2,2);

    if ($f1 < $f2) {
      return -1;
    } elsif ($f1 > $f2) {
      return 1;
    } else {
      return index_compare ($r1,$r2);
    }
  }
}

sub oid_diff ($$) {
  my($base, $full) = @_;
  my $base_dotnot = join ('.',@{$base});
  my $full_dotnot = BER::pretty_oid ($full);

  return undef unless substr ($full_dotnot, 0, length $base_dotnot)
    eq $base_dotnot
      && substr ($full_dotnot, length $base_dotnot, 1) eq '.';
  substr ($full_dotnot, length ($base_dotnot)+1);
}

# Pretty_address returns a human-readable representation of an IPv4 or IPv6 address.
sub pretty_address {
    my($addr) = shift;
    my($port, $addrunpack, $addrstr);

    # Disable strict subs to stop old versions of perl from
    # complaining about AF_INET6 when Socket6 is not available

    if( (defined $ipv6_addr_len) && (length $addr == $ipv6_addr_len)) {
	($port,$addrunpack) = unpack_sockaddr_in6 ($addr);
	$addrstr = inet_ntop (AF_INET6(), $addrunpack);
    } else {
	($port,$addrunpack) = unpack_sockaddr_in ($addr);
	$addrstr = inet_ntoa ($addrunpack);
    }

    return sprintf ("[%s].%d", $addrstr, $port);
}

sub version { $VERSION; }


sub error_return ($$) {
    my ($this,$message) = @_;
    $SNMP_Session::errmsg = $message;
    unless ($SNMP_Session::suppress_warnings) {
	$message =~ s/^/  /mg;
	carp ("Error:\n".$message."\n");
    }
    return undef;
}

sub error ($$) {
    my ($this,$message) = @_;
    my $session = $this->to_string;
    $SNMP_Session::errmsg = $message."\n".$session;
    unless ($SNMP_Session::suppress_warnings) {
	$session =~ s/^/  /mg;
	$message =~ s/^/  /mg;
	carp ("SNMP Error:\n".$SNMP_Session::errmsg."\n");
    }
    return undef;
}

sub ber_error ($$) {
  my ($this,$type) = @_;
  my ($errmsg) = $BER::errmsg;

  $errmsg =~ s/^/  /mg;
  return $this->error ("$type:\n$errmsg");
}

package SNMPv1_Session;

use strict qw(vars subs);	# see above
use vars qw(@ISA);
use SNMP_Session;
use Socket;
use BER;
use IO::Socket;
use Carp;

BEGIN {
    if($SNMP_Session::ipv6available) {
	import IO::Socket::INET6;
	Socket6->import(qw(inet_pton getaddrinfo));
	#import Socket6;
    }
}

@ISA = qw(SNMP_Session);

sub snmp_version { 0 }

# Supports both IPv4 and IPv6.
# Numeric IPv6 addresses must be passed between square brackets []
sub open {
    my($this,
       $remote_hostname,$community,$port,
       $max_pdu_len,$local_port,$max_repetitions,
       $local_hostname,$ipv4only) = @_;
    my($remote_addr,$socket,$sockfamily);

    $ipv4only = 1 unless defined $ipv4only;
    $sockfamily = AF_INET;

    $community = 'public' unless defined $community;
    $port = SNMP_Session::standard_udp_port unless defined $port;
    $max_pdu_len = 8000 unless defined $max_pdu_len;
    $max_repetitions = $default_max_repetitions
	unless defined $max_repetitions;

    if ($ipv4only || ! $SNMP_Session::ipv6available) {
	# IPv4-only code, uses only Socket and INET calls
    if (defined $remote_hostname) {
	$remote_addr = inet_aton ($remote_hostname)
	    or return $this->error_return ("can't resolve \"$remote_hostname\" to IP address");
    }
    if ($SNMP_Session::recycle_socket && exists $the_socket{$sockfamily}) {
	$socket = $the_socket{$sockfamily};
    } else {
	$socket = IO::Socket::INET->new(Proto => 17,
					Type => SOCK_DGRAM,
					LocalAddr => $local_hostname,
					LocalPort => $local_port)
	    || return $this->error_return ("creating socket: $!");
	$the_socket{$sockfamily} = $socket
	    if $SNMP_Session::recycle_socket;
    }
    $remote_addr = pack_sockaddr_in ($port, $remote_addr)
	if defined $remote_addr;
    } else {
	# IPv6-capable code. Will use IPv6 or IPv4 depending on the address.
	# Uses Socket6 and INET6 calls.

	# If it's a numeric IPv6 addresses, remove square brackets
	if ($remote_hostname =~ /^\[(.*)\]$/) {
	    $remote_hostname = $1;
	}

	my (@res, $socktype_tmp, $proto_tmp, $canonname_tmp);
	@res = getaddrinfo($remote_hostname, $port, AF_UNSPEC, SOCK_DGRAM);
	($sockfamily, $socktype_tmp, $proto_tmp, $remote_addr, $canonname_tmp) = @res;
	if (scalar(@res) < 5) {
	    return $this->error_return ("can't resolve \"$remote_hostname\" to IPv6 address");
	}

	if ($SNMP_Session::recycle_socket && exists $the_socket{$sockfamily}) {
	    $socket = $the_socket{$sockfamily};
	} elsif ($sockfamily == AF_INET) {
	    $socket = IO::Socket::INET->new(Proto => 17,
					    Type => SOCK_DGRAM,
					    LocalAddr => $local_hostname,
					    LocalPort => $local_port)
	         || return $this->error_return ("creating socket: $!");
	} else {
	    $socket = IO::Socket::INET6->new(Proto => 17,
					     Type => SOCK_DGRAM,
					     LocalAddr => $local_hostname,
					     LocalPort => $local_port)
	         || return $this->error_return ("creating socket: $!");
	    $the_socket{$sockfamily} = $socket
	        if $SNMP_Session::recycle_socket;
	}
    }
    bless {
	   'sock' => $socket,
	   'sockfileno' => fileno ($socket),
	   'community' => $community,
	   'remote_hostname' => $remote_hostname,
	   'remote_addr' => $remote_addr,
	   'sockfamily' => $sockfamily,
	   'max_pdu_len' => $max_pdu_len,
	   'pdu_buffer' => '\0' x $max_pdu_len,
	   'request_id' => (int (rand 0x10000) << 16)
	       + int (rand 0x10000) - 0x80000000,
	   'timeout' => $default_timeout,
	   'retries' => $default_retries,
	   'backoff' => $default_backoff,
	   'debug' => $default_debug,
	   'error_status' => 0,
	   'error_index' => 0,
	   'default_max_repetitions' => $max_repetitions,
	   'use_getbulk' => 1,
	   'lenient_source_address_matching' => 1,
	   'lenient_source_port_matching' => 1,
	   'avoid_negative_request_ids' => $SNMP_Session::default_avoid_negative_request_ids,
	   'use_16bit_request_ids' => $SNMP_Session::default_use_16bit_request_ids,
	   'capture_buffer' => undef,
	  };
}

sub open_trap_session (@) {
    my ($this, $port) = @_;
    $port = 162 unless defined $port;
    return $this->open (undef, "", 161, undef, $port);
}

sub sock { $_[0]->{sock} }
sub sockfileno { $_[0]->{sockfileno} }
sub remote_addr { $_[0]->{remote_addr} }
sub pdu_buffer { $_[0]->{pdu_buffer} }
sub max_pdu_len { $_[0]->{max_pdu_len} }
sub default_max_repetitions {
    defined $_[1]
	? $_[0]->{default_max_repetitions} = $_[1]
	    : $_[0]->{default_max_repetitions} }
sub debug { defined $_[1] ? $_[0]->{debug} = $_[1] : $_[0]->{debug} }

sub close {
    my($this) = shift;
    ## Avoid closing the socket if it may be shared with other session
    ## objects.
    if (! exists $the_socket{$this->{sockfamily}}
	or $this->sock ne $the_socket{$this->{sockfamily}}) {
	close ($this->sock) || $this->error ("close: $!");
    }
}

sub wrap_request {
    my($this) = shift;
    my($request) = shift;

    encode_sequence (encode_int ($this->snmp_version),
		     encode_string ($this->{community}),
		     $request)
      || return $this->ber_error ("wrapping up request PDU");
}

my @error_status_code = qw(noError tooBig noSuchName badValue readOnly
			   genErr noAccess wrongType wrongLength
			   wrongEncoding wrongValue noCreation
			   inconsistentValue resourceUnavailable
			   commitFailed undoFailed authorizationError
			   notWritable inconsistentName);

sub unwrap_response_5b {
    my ($this,$response,$tag,$oids,$errorp) = @_;
    my ($community,$request_id,@rest,$snmpver);

    ($snmpver,$community,$request_id,
     $this->{error_status},
     $this->{error_index},
     @rest)
	= decode_by_template ($response, "%{%i%s%*{%i%i%i%{%@",
			      $tag);
    return $this->ber_error ("Error decoding response PDU")
      unless defined $snmpver;
    return $this->error ("Received SNMP response with unknown snmp-version field $snmpver")
	unless $snmpver == $this->snmp_version;
    if ($this->{error_status} != 0) {
      if ($errorp) {
	my ($oid, $errmsg);
	$errmsg = $error_status_code[$this->{error_status}] || $this->{error_status};
	$oid = $oids->[$this->{error_index}-1]
	  if $this->{error_index} > 0 && $this->{error_index}-1 <= $#{$oids};
	$oid = $oid->[0]
	  if ref($oid) eq 'ARRAY';
	return ($community, $request_id,
		$this->error ("Received SNMP response with error code\n"
			      ."  error status: $errmsg\n"
			      ."  index ".$this->{error_index}
			      .(defined $oid
				? " (OID: ".&BER::pretty_oid($oid).")"
				: "")));
      } else {
	if ($this->{error_index} == 1) {
	  @rest[$this->{error_index}-1..$this->{error_index}] = ();
	}
      }
    }
    ($community, $request_id, @rest);
}

sub send_query ($$) {
    my ($this,$query) = @_;
    send ($this->sock,$query,0,$this->remote_addr);
}

## Compare two sockaddr_in structures for equality.  This is used when
## matching incoming responses with outstanding requests.  Previous
## versions of the code simply did a bytewise comparison ("eq") of the
## two sockaddr_in structures, but this didn't work on some systems
## where sockaddr_in contains other elements than just the IP address
## and port number, notably FreeBSD.
##
## We allow for varying degrees of leniency when checking the source
## address.  By default we now ignore it altogether, because there are
## agents that don't respond from UDP port 161, and there are agents
## that don't respond from the IP address the query had been sent to.
##
## The address family is stored in the session object. We could use
## sockaddr_family() to determine it from the sockaddr, but this function
## is only available in recent versions of Socket.pm.
sub sa_equal_p ($$$) {
    my ($this, $sa1, $sa2) = @_;
    my ($p1,$a1,$p2,$a2);

    # Disable strict subs to stop old versions of perl from
    # complaining about AF_INET6 when Socket6 is not available
    if($this->{'sockfamily'} == AF_INET) {
	# IPv4 addresses
	($p1,$a1) = unpack_sockaddr_in ($sa1);
	($p2,$a2) = unpack_sockaddr_in ($sa2);
    } elsif($this->{'sockfamily'} == AF_INET6()) {
	# IPv6 addresses
	($p1,$a1) = unpack_sockaddr_in6 ($sa1);
	($p2,$a2) = unpack_sockaddr_in6 ($sa2);
    } else {
	return 0;
    }
    use strict "subs";

    if (! $this->{'lenient_source_address_matching'}) {
	return 0 if $a1 ne $a2;
    }
    if (! $this->{'lenient_source_port_matching'}) {
	return 0 if $p1 != $p2;
    }
    return 1;
}

sub receive_response_3 {
    my ($this, $response_tag, $oids, $errorp, $dont_block_p) = @_;
    my ($remote_addr);
    my $flags = 0;
    $flags = $dont_wait_flags if defined $dont_block_p and $dont_block_p;
    $remote_addr = recv ($this->sock,$this->{'pdu_buffer'},$this->max_pdu_len,$flags);
    return $this->error ("receiving response PDU: $!")
	unless defined $remote_addr;
    return $this->error ("short (".length $this->{'pdu_buffer'}
			 ." bytes) response PDU")
	unless length $this->{'pdu_buffer'} > 2;
    my $response = $this->{'pdu_buffer'};
    ##
    ## Check whether the response came from the address we've sent the
    ## request to.  If this is not the case, we should probably ignore
    ## it, as it may relate to another request.
    ##
    if (defined $this->{'remote_addr'}) {
	if (! $this->sa_equal_p ($remote_addr, $this->{'remote_addr'})) {
	    if ($this->{'debug'} && !$SNMP_Session::recycle_socket) {
		carp ("Response came from ".&SNMP_Session::pretty_address($remote_addr)
		      .", not ".&SNMP_Session::pretty_address($this->{'remote_addr'}))
			unless $SNMP_Session::suppress_warnings;
	    }
	    return 0;
	}
    }
    $this->{'last_sender_addr'} = $remote_addr;
    my ($response_community, $response_id, @unwrapped)
	= $this->unwrap_response_5b ($response, $response_tag,
				     $oids, $errorp);
    if ($response_community ne $this->{community}
        || $response_id ne $this->{request_id}) {
	if ($this->{'debug'}) {
	    carp ("$response_community != $this->{community}")
		unless $SNMP_Session::suppress_warnings
		    || $response_community eq $this->{community};
	    carp ("$response_id != $this->{request_id}")
		unless $SNMP_Session::suppress_warnings
		    || $response_id == $this->{request_id};
	}
	return 0;
    }
    if (!defined $unwrapped[0]) {
	$this->{'unwrapped'} = undef;
	return undef;
    }
    $this->{'unwrapped'} = \@unwrapped;
    return length $this->pdu_buffer;
}

sub receive_trap {
    my ($this) = @_;
    my ($remote_addr, $iaddr, $port, $trap);
    $remote_addr = recv ($this->sock,$this->{'pdu_buffer'},$this->max_pdu_len,0);
    return undef unless $remote_addr;

    if( (defined $ipv6_addr_len) && (length $remote_addr == $ipv6_addr_len)) {
	($port,$iaddr) = unpack_sockaddr_in6($remote_addr);
    } else {
	($port,$iaddr) = unpack_sockaddr_in($remote_addr);
    }

    $trap = $this->{'pdu_buffer'};
    return ($trap, $iaddr, $port);
}

sub describe {
    my($this) = shift;
    print $this->to_string (),"\n";
}

sub to_string {
    my($this) = shift;
    my ($class,$prefix);

    $class = ref($this);
    $prefix = ' ' x (length ($class) + 2);
    ($class
     .(defined $this->{remote_hostname}
       ? " (remote host: \"".$this->{remote_hostname}."\""
       ." ".&SNMP_Session::pretty_address ($this->remote_addr).")"
       : " (no remote host specified)")
     ."\n"
     .$prefix."  community: \"".$this->{'community'}."\"\n"
     .$prefix." request ID: ".$this->{'request_id'}."\n"
     .$prefix."PDU bufsize: ".$this->{'max_pdu_len'}." bytes\n"
     .$prefix."    timeout: ".$this->{timeout}."s\n"
     .$prefix."    retries: ".$this->{retries}."\n"
     .$prefix."    backoff: ".$this->{backoff}.")");
##    sprintf ("SNMP_Session: %s (size %d timeout %g)",
##    &SNMP_Session::pretty_address ($this->remote_addr),$this->max_pdu_len,
##	       $this->timeout);
}

### SNMP Agent support
### contributed by Mike McCauley <mikem@open.com.au>
###
sub receive_request {
    my ($this) = @_;
    my ($remote_addr, $iaddr, $port, $request);

    $remote_addr = recv($this->sock, $this->{'pdu_buffer'}, 
			$this->{'max_pdu_len'}, 0);
    return undef unless $remote_addr;

    if( (defined $ipv6_addr_len) && (length $remote_addr == $ipv6_addr_len)) {
	($port,$iaddr) = unpack_sockaddr_in6($remote_addr);
    } else {
	($port,$iaddr) = unpack_sockaddr_in($remote_addr);
    }

    $request = $this->{'pdu_buffer'};
    return ($request, $iaddr, $port);
}

sub decode_request {
    my ($this, $request) = @_;
    my ($snmp_version, $community, $requestid, $errorstatus, $errorindex, $bindings);

    ($snmp_version, $community, $requestid, $errorstatus, $errorindex, $bindings)
	= decode_by_template ($request, "%{%i%s%*{%i%i%i%@", SNMP_Session::get_request);
    if (defined $snmp_version)
    {
	# Its a valid get_request
	return(SNMP_Session::get_request, $requestid, $bindings, $community);
    }

    ($snmp_version, $community, $requestid, $errorstatus, $errorindex, $bindings)
	= decode_by_template ($request, "%{%i%s%*{%i%i%i%@", SNMP_Session::getnext_request);
    if (defined $snmp_version)
    {
	# Its a valid getnext_request
	return(SNMP_Session::getnext_request, $requestid, $bindings, $community);
    }

    ($snmp_version, $community, $requestid, $errorstatus, $errorindex, $bindings)
	= decode_by_template ($request, "%{%i%s%*{%i%i%i%@", SNMP_Session::set_request);
    if (defined $snmp_version)
    {
	# Its a valid set_request
	return(SNMP_Session::set_request, $requestid, $bindings, $community);
    }

    # Something wrong with this packet
    # Decode failed
    return undef;
}

package SNMPv2c_Session;
use strict qw(vars subs);	# see above
use vars qw(@ISA);
use SNMP_Session;
use BER;
use Carp;

@ISA = qw(SNMPv1_Session);

sub snmp_version { 1 }

sub open {
    my $session = SNMPv1_Session::open (@_);
    return undef unless defined $session;
    return bless $session;
}

## map_table_start_end using get-bulk
##
sub map_table_start_end ($$$$$$) {
    my ($session, $columns, $mapfn, $start, $end, $max_repetitions) = @_;

    my @encoded_oids;
    my $call_counter = 0;
    my $base_index = $start;
    my $ncols = @{$columns};
    my @collected_values = ();

    if (! $session->{'use_getbulk'}) {
	return SNMP_Session::map_table_start_end
	    ($session, $columns, $mapfn, $start, $end, $max_repetitions);
    }
    $max_repetitions = $session->default_max_repetitions
	unless defined $max_repetitions;

    for (;;) {
	foreach (@encoded_oids = @{$columns}) {
	    $_=encode_oid (@{$_},split '\.',$base_index)
		|| return $session->ber_error ("encoding OID $base_index");
	}
	if ($session->getbulk_request_response (0, $max_repetitions,
						@encoded_oids)) {
	    my $response = $session->pdu_buffer;
	    my ($bindings) = $session->decode_get_response ($response);
	    my @colstack = ();
	    my $k = 0;
	    my $j;

	    my $min_index = undef;

	    my @bases = @{$columns};
	    my $n_bindings = 0;
	    my $binding;

	    ## Copy all bindings into the colstack.
	    ## The colstack is a vector of vectors.
	    ## It contains one vector for each "repeater" variable.
	    ##
	    while ($bindings ne '') {
		($binding, $bindings) = decode_sequence ($bindings);
		my ($oid, $value) = decode_by_template ($binding, "%O%@");

		push @{$colstack[$k]}, [$oid, $value];
		++$k; $k = 0 if $k >= $ncols;
	    }

	    ## Now collect rows from the column stack:
	    ##
	    ## Iterate through the column stacks to find the smallest
	    ## index, collecting the values for that index in
	    ## @collected_values.
	    ##
	    ## As long as a row can be assembled, the map function is
	    ## called on it and the iteration proceeds.
	    ##
	    $base_index = undef;
	  walk_rows_from_pdu:
	    for (;;) {
		my $min_index = undef;

		for ($k = 0; $k < $ncols; ++$k) {
		    $collected_values[$k] = undef;
		    my $pair = $colstack[$k]->[0];
		    unless (defined $pair) {
			$min_index = undef;
			last walk_rows_from_pdu;
		    }
		    my $this_index
			= SNMP_Session::oid_diff ($columns->[$k], $pair->[0]);
		    if (defined $this_index) {
			my $cmp
			    = !defined $min_index
				? -1
				    : SNMP_Session::index_compare
					($this_index, $min_index);
			if ($cmp == -1) {
			    for ($j = 0; $j < $k; ++$j) {
				unshift (@{$colstack[$j]},
					 [$min_index,
					  $collected_values[$j]]);
				$collected_values[$j] = undef;
			    }
			    $min_index = $this_index;
			}
			if ($cmp <= 0) {
			    $collected_values[$k] = $pair->[1];
			    shift @{$colstack[$k]};
			}
		    }
		}
		($base_index = undef), last
		    if !defined $min_index;
		last
		    if defined $end
		    and SNMP_Session::index_compare ($min_index, $end) >= 0;
		&$mapfn ($min_index, @collected_values);
		++$call_counter;
		$base_index = $min_index;
	    }
	} else {
	    return undef;
	}
	last if !defined $base_index;
	last
	    if defined $end
	    and SNMP_Session::index_compare ($base_index, $end) >= 0;
    }
    $call_counter;
}

1;
