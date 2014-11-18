#!/usr/bin/perl

our %CMD_FN_MAP =
(
MENU_MAIN => \&MENU_MAIN, #

MENU_DISC_OPT => \&MENU_DISC_OPT, #
MENU_IPENDPT_OPT => \&MENU_IPENDPT_OPT, #

RUN_DISC_REPORT => \&FN_RUN_DISC_REPORT, #
RUN_IPENDPT_REPORT => \&FN_RUN_IPENDPT_REPORT, #
);

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
print 'The filename to delivered: ';
chomp($choice = <STDIN>);
$disconnect_report = $choice;

return 'RUN_DISC_REPORT'
}

sub FN_RUN_DISC_REPORT
{
print "\nYour Disconnect report is running \n";
print "The report name is: ".$disconnect_report."\n";
return '';
}

sub MENU_IPENDPT_OPT {
print "\n IP-Endpoint Report\n";
print 'The filename to delivered: ';
chomp($choice = <STDIN>);
$ipendpoint_report = $choice;

return 'RUN_IPENDPT_REPORT'
}

sub FN_RUN_IPENDPT_REPORT
{
print "\nYour IP-Endpoint report is running \n";
print "The report name is: ".$ipendpoint_report."\n";
return '';
}
my $next = MENU_MAIN();
while (1)
{
exit if !$next;
die if !exists $CMD_FN_MAP{uc($next)};
$next = &{$CMD_FN_MAP{uc($next)}}();
} 