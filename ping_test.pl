#!/usr/bin/perl

=pod

=head1 NAME

ping_test.pl

=head1 DESCRIPTION

ping_test.pl is the first step of ping_logger. It performs that actual ping
from this host, gathers the results and sends them to the logging host.


=head1 DEPENDANCIES

ping_test.pl requires the following modules to already be in the local 
Perl install:
    
=over 

=item MIME::Base64

=item Statistics::Basic

=item XML::Twig

=item Compress::Bzip2

=back

=cut

use strict;
use MIME::Base64;
use Statistics::Basic qw(:all nofill);
use XML::Twig;
use Compress::Bzip2;

my $starttime = time;

if ($ARGV[0]) {
    if (-f $ARGV[0]) {
        open(CONF, $ARGV[0]);
    }
    else {
        die "Specified configuration file '" . $ARGV[0] 
            . "' is not a file, aborting.\n";
    }
}
else {
    die "Configuration file not specified on command line, aborting.\n";
}

=pod

=head1 CALLING SYNTAX

ping_test.pl I<configfilepath>

I<configfilepath> is required. Only the first command line parameter is used.
The I<configfilepath> configuration file is ASCII, each line is processed in 
order found. If duplicate keys are found, the last one in the file is the 
only one that applies. Comments are indicated with pound (#) - the pound and 
everything to the end of the line are discarded.

The following keys are defined. Any other key in the file is ignored. There 
are no default values for any of these keys. A value must be supplied for
all of these keys or the script will abort with an error.

=over

=item I<target> - The host as requested from the local ping command, so any 
form of hostname that your ping command accepts is valid.

=item I<samples> - The number of pings to send to the target. This value should 
be lower than the number of seconds between the runs of ping_test.pl

=item I<description> - During reporting, this is presented as the name of this 
set of results. If you are gathering samples from multiple targets and 
running ping_test.pl on multiple computers, you will want the description of 
each to be unique

=item I<loghost> - The host where results are sent and (if configured at the 
loghost) processed. The connection to the I<loghost> is made by SSH - the 
assumption is that this connection can be made without requiring any 
password or passphrase to be supplied at the command line or STDIN when
connecting. This must be configured with SSH tools prior to running
ping_test.pl

=item I<logcmd> - The command on the I<loghost> to execute. Normally this is
the full path to ping_logger.pl

=item I<logoption> - Optional string to put between logcmd and encoded report. 
This is available in order to override the configuration file when using 
ping_logger.pl

=back

=cut

my $target;
my $samples;
my $loghost;
my $description;
my $logcmd;
my $logoption;
my $twig;
$twig = XML::Twig->new();
my $root;
$root = XML::Twig::Elt->new('PingResult');
{
    my $elt = XML::Twig::Elt->new('FormatVersion',,2);
    $elt->paste(last_child => $root);
}
$twig->set_root($root);
{
    my $elt = XML::Twig::Elt->new('Starttime',,$starttime);
    $elt->paste(last_child => $root);
}

{
    my $line;
    while ($line = <CONF>) {
        $line =~ s/\#*\Z//;
        $line =~ s/\s\Z//;
        if ($line =~ m/=/) {
        	my $key;
        	my $value;
        	($key, $value) = split('=', $line, 2);
        	if (lc $key eq 'target') {
        	    $target = $value;
        	    my $elt = XML::Twig::Elt->new('Target',,$value);
        	    $elt->paste(last_child => $root);
        	}
        	elsif (lc $key eq 'samples') {
        	    $samples = $value;
        	    my $elt = XML::Twig::Elt->new('Samples',,$value);
        	    $elt->paste(last_child => $root);
        	}
        	elsif (lc $key eq 'description') {
        	    $description = $value;
                my $parser = XML::Parser::Expat->new();
        	    my $elt = XML::Twig::Elt->new('Description',,$parser->xml_escape($value));
        	    $elt->paste(last_child => $root);
        	}
        	elsif (lc $key eq 'loghost') {
        	    $loghost = $value;
        	}
        	elsif (lc $key eq 'logcmd') {
        	    $logcmd = $value;
        	}
        	elsif (lc $key eq 'logoption') {
        	    $logoption = $value;
        	}
        }
        else {
    	# No equal sign? Ignore the line
        }
    }
}

close(CONF);


if ($target && $samples && $loghost && $description && $logcmd) {
    my $pingcmd;
    my $result;
    my @resultlines;
    my $result_packed;
    my $stddev;
    my $rttstats;
    my $countstats;
    my $ptrans;
    my $precv;
    my $ploss;
    my $ptime;
    my $rttavg;
    my $rttmin;
    my $rttmax;
    my $rttmdev;
    my @pingtimes;
    $pingcmd = "/bin/ping -n -c $samples $target";
    $result = `$pingcmd`;
    {
        my $parser = XML::Parser::Expat->new();
        my $elt = XML::Twig::Elt->new('#CDATA' => $parser->xml_escape($result))->wrap_in('ResultsPacked');
        $elt->paste(last_child => $root);
    }
    @resultlines = split("\n", $result);
    $result_packed = $result;
    $result_packed =~ s/\n/~~~/g;
    $rttstats = pop(@resultlines);
    $countstats = pop(@resultlines);
    @pingtimes = ();
    my $foundtimes = 0;
    my $pingtimeselt = XML::Twig::Elt->new('Pingtimes');
    my $line;
    foreach $line (@resultlines) {
    	if ($line =~ /time=(\d+\.?\d*) ms/) {
    	    my $timesample = $1;
    	    push(@pingtimes, $timesample);
    	    my $elt = XML::Twig::Elt->new('Time',,$timesample);
    	    $elt->paste(last_child => $pingtimeselt);
    	    $foundtimes = 1;
    	}
    }
    if ($foundtimes) {
    	$stddev = stddev(@pingtimes);
    	$pingtimeselt->paste(last_child => $root);
    	my $elt = XML::Twig::Elt->new('Stddev',,$stddev);
    	$elt->paste(last_child => $root);
    }

=pod

=head1 LOCAL PING RESULT FORMATS

There are two formats of summary output from ping that are recognised based on 
the second to the last line of output:
    
=over

=item C<\A(\d+) packets transmitted, (\d+) packets received, (\d+)\% packet loss\s*\Z>

=item C<\A(\d+) packets transmitted, (\d+) received, (\d+)\% packet loss, time (\d+)>

=back

Any other form of ping output means that the results of the entire test
 will be discarded.

=cut
    
    if ($rttstats =~ /packets transmitted/) {   
    	# older ping when no results returned  
	    $countstats = $rttstats;
	    $rttstats = "";
    }
    if ($countstats =~ /\A(\d+) packets transmitted, (\d+) packets received, (\d+)\% packet loss\s*\Z/) {
    	$countstats = "$1 packets transmitted, $2 received, $3" . '% packet loss, time 0';
    }
    if ($countstats =~ /\A(\d+) packets transmitted, (\d+) received, (\d+)\% packet loss, time (\d+)/) {
    	$ptrans = $1;
    	$precv = $2;
    	$ploss = $3; 
    	$ptime = $4;
    	if ($rttstats =~ /\A\s*\Z/) {
    	    $rttstats = "rtt min/avg/max/mdev = 0.0/0.0/0.0 ms";
    	}
    	if ($rttstats =~ /\Around-trip min\/avg\/max = (.+)\/(.+)\/(.+) ms/) {
    	    $rttstats = "rtt min/avg/max/mdev = $1/$2/$3/0.0 ms";
    	}
    	if ($rttstats =~ /\Artt min\/avg\/max\/mdev = (.+) ms/) {
    	    ($rttmin, $rttavg, $rttmax, $rttmdev) = split('/', $1);
    	    {
    	        my $elt = XML::Twig::Elt->new('Ptrans',,$ptrans);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Precv',,$precv);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Ploss',,$ploss);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Ptime',,$ptime);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Rttmin',,$rttmin);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Rttavg',,$rttavg);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Rttmax',,$rttmax);
    	        $elt->paste(last_child => $root);
    	    }
    	    {
    	        my $elt = XML::Twig::Elt->new('Rttmdev',,$rttmdev);
    	        $elt->paste(last_child => $root);
    	    }
    
=pod

=head1 TRANSFER PROTOCOL / REPORT FORMAT

After the ping results are gathered, they are sent to the I<loghost> by making
a ssh connection as the current user to the I<loghost> and issuing the command
I<logcmd> with one parameter - the report in Base64 encoding.

The report itself is an XML file that is bzip2 compressed with the following
tags (the order listed here is not the order they are writen to the XML file): 

=over

=item PingResult = this is the root element to the XML tree

=item FormatVersion = the value 2 - the prior format was implied to be 
version 1, but was not listed anywhere within the file itself.

=item Starttime = The number of seconds since the start of the epoch when 
ping_test.pl was started

=item Target = The value of I<target>

=item Description = The value of I<description>

=item Samples = The value of I<samples>

=item Ptrans = The number of packets actually transmitted - normally this would
be equal to I<samples> unless the ping child command was killed before it 
completed.

=item Precv = The number of packets received

=item Ploss = The number of packets that have been lost during the test. 

=item Ptime = The elapsed time of the ping test (not really useful)

=item Rttmin = The fastest ping out of the bunch

=item Rttagv = The average ping time

=item Rttmax = The slowest ping out of the bunch

=item Rttmdev = The mean deviatition as reported by ping

=item Stddev = The standard deviation as calculated by 
Statistics::Basic->stddev

=item Pingtimes = The time of all samples as child <Time> tags

=item ResultsPacked = The raw output from ping

=back

=cut
            my $tosend; 
    	    $tosend = memBzip($twig->sprint);
    	    if ($logoption) {
    	        system('/usr/bin/ssh', $loghost, $logcmd, $logoption, encode_base64($tosend, ''));
    	    }
    	    else {
    	        system('/usr/bin/ssh', $loghost, $logcmd, encode_base64($tosend, ''));
    	    }
    	}
    	else {
    	    die "Rttstats badly formatted: '$rttstats', aborting.\n";
    	}
    }
    else {
    	die "Countstats badly formatted: '$countstats', aborting.\n";
    }
}
else {
    die "Missing configuration item. One of target, samples, loghost, description or logcmd. Aborting.\n";
}

=pod

=head1 SECURITY CONSIDERATIONS

The value of the I<samples> and I<target> keys from the configuration file are 
supplied to the command line on the computer where ping_test.pl is run.

The value of the I<logcmd> key is executed on the command line via SSH on 
I<loghost>. 

=cut
