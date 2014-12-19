Avaya-Utility-Script
====================

Combines multiple report subroutines into on application
Avaya-Aura-CM-Script
====================
Over the course of time, I've come to find that there are several data elements that cannot easily be gathered through the traditional Avaya System Administration Terminal or System Manager. 

For example, I find it useful to perform an audit of all Avaya H323 endpoints before and after upgrades. In the event you lose an endpoint, knowing the mac-address can significantly help you track down the endpoint to a specific port. Unfortunately, the only means of doing this is to perform a status station on each and every endpoint - not very practical or efficient when you're dealing with thousands of endpoints.

In addition, there is useful information about the end-points that can only be gathered via SNMP. For example, the serial number of the phone, the list of alternate gate keepers, active DHCP server, etc. Unless you have expensive management tools already actively managing these devices, it can be extremely difficult to gather this information.

Another example, is simply generating a "trusted" list of disconnected stations.  While you can do a "display error" and filter on a specific error type (ie. 3329), I've found this method to generate inaccacurate results.  Statusing each station and noting the state (disconnected or out-of-service) is the most accurate.

Another example would be searching vectors for specific values.  If you want to search vectors for all extensions that are associated with a messaging command, there's no way to check without displaying each and every vector.

This ever-growing application is a collection of routines I've put together to quickly generate system reports as briefly described above.


A little bit about some of the routines:


The $MIB1 and $MIB2 variables in the SNMP subroutine can be changed to any Avaya endpoint OID you want to snag.

The "$PBX" variable defines the CM instance. The connection details of each instance are defined in the OSSI Module (cli_ossi.pm).

The cli_ossi module included is a modified version of Ben Roy's Definity.pm which is used to interface with Communication Manager via XML Interface. https://github.com/benroy73/pbxd.

The SNMP modules included should not be confused with the SNMP perl modules found in CPAN (i.e. Net::SNMP). The modules I've included were previously maintained by http://www.switch.ch/misc/leinen/snmp/perl/ They are now publicly available on code.google.com/p/snmp-session The entire package which includes all three modules can be downloaded from https://snmp-session.googlecode.com/files/SNMP_Session-1.13.tar.gz
