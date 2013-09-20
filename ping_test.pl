#!/usr/bin/perl

use MIME::Base64;
use Statistics::Basic qw(:all nofill);

$starttime = time;

if (-f $ARGV[0]) {
    open(CONF, $ARGV[0]);
}
else {
    die "Configuration file not specified, aborting.\n";
}

while ($line = <CONF>) {
    $line =~ s/\#*\Z//;
    $line =~ s/\s\Z//;
    if ($line =~ m/=/) {
	my $key;
	my $value;
	($key, $value) = split('=', $line, 2);
	if (lc $key eq 'target') {
	    $target = $value;
	}
	elsif (lc $key eq 'samples') {
	    $samples = $value;
	}
	elsif (lc $key eq 'loghost') {
	    $loghost = $value;
	}
	elsif (lc $key eq 'description') {
	    $description = $value;
	}
	elsif (lc $key eq 'logcmd') {
	    $logcmd = $value;
	}
    }
    else {
	# No equal sign? Ignore the line
    }
}

close(CONF);

if ($target && $samples && $loghost && $description && $logcmd) {
    $pingcmd = "/bin/ping -n -c $samples $target";
    $result = `$pingcmd`;
    @resultlines = split("\n", $result);
    $result_packed = $result;
    $result_packed =~ s/\n/~~~/g;
    $rttstats = pop(@resultlines);
    $countstats = pop(@resultlines);
    @pingtimes = ();
    foreach $line (@resultlines) {
	if ($line =~ /time=(\d+\.?\d*) ms/) {
	    push(@pingtimes, $1);
	}
    }
    if (@pingtimes) {
	$stddev = stddev(@pingtimes);
    }
    
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
	    $submitreport = join("\n",
		'starttime=' . $starttime,
		'target=' . $target,
		'description=' . $description, 
		'samples=' . $samples,
		'ptrans=' . $ptrans,
		'precv=' . $precv,
		'ploss=' . $ploss,
		'ptime=' . $ptime,
		'rttmin=' . $rttmin,
		'rttavg=' . $rttavg,
		'rttmax=' . $rttmax,
		'rttmdev=' . $rttmdev,
		'stddev=' . $stddev,
		'pingtimes=' . join(':', @pingtimes),
		'resultpacked=' . $result_packed
	    );
	    system('/usr/bin/ssh', $loghost, $logcmd, encode_base64($submitreport, ''));
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
