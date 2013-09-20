#!/usr/bin/perl

use strict;

use HTML::Template;
use File::Spec;
use File::Copy;
use Statistics::Basic qw(:all nofill);
use Number::Format;

my $html_finalized = 0;

my $reportstarttime = time;
my $datumcutofftime = $reportstarttime - 3600;
my $reporthumantime = localtime($reportstarttime);
my @reporttime = localtime($reportstarttime);

my @finalhtml;
my @simplehtml;
my @simplesummary;

my %datumstats;
my $description;

my $datadir = "/var/pinglogger/";
my $simplehtmlfile = "/var/www/status/index.html";
my $htmlfile = "/var/www/status/details.html";
my $htmlpath = "/var/www/status/";

my %datumreports;
my %datumreportsimple;

if (-d $datadir) {
    if (opendir(PARENT, $datadir)) {
	my @data;
	my $ent;
	push (@finalhtml, '<html><title>NNE Network Status - Detail</title><body>');
	push (@finalhtml, 'This report <a href="https://helpdesk.nnenews.com/status/details.html"><b>https://helpdesk.nnenews.com/status/details.html</b></a> generated starting at ' . $reporthumantime . ". This report is updated every five minutes.\n");
	push (@finalhtml, '<p>See <a href="https://helpdesk.nnenews.com/projects/nne/wiki/Pinglogger">Pinglogger wiki entry</a> in NNE helpdesk for documentation (requires login).');
	{
	    my $year = $reporttime[5] + 1900;
	    my $month = $reporttime[4] + 1;
	    my $day = $reporttime[3];
	    my $hour = $reporttime[2];
	    my $url = sprintf('https://helpdesk.nnenews.com/status/%d/%d/%d/%d.html', $year, $month, $day, $hour) ;	    
	    push (@finalhtml, '<p>For historic access to this report, see <a href="' .$url . '">' . $url . '</a>');
	}
	while ($ent = readdir(PARENT)) {
	    unless ($ent =~ m/[^[:xdigit:]]/) {
		my $datum;
		$datum = File::Spec->catdir($datadir, $ent); 
		if (-d $datum) {
		    push (@data, $datum); 
		}
		else {
		    # silently ignore non directories
		}
	    }
	    else {
		# silently ignore anything with nonnumerics in the name
	    }
	}
	closedir(PARENT);
	{
	    my $datum;
	    foreach $datum (@data) {
		process_datum($datum);
	    }
	}
	{
	    my $key;
	    my $alt = 0;
	    push(@simplehtml, '<table border="1" style="border:none;border-collapse:collapse">');
	    foreach $key (sort keys %datumreports) {
		push (@finalhtml, $datumreports{$key});
		if ($datumreportsimple{$key} =~ /\S/) {
		    if ($alt == 0) {
			push(@simplehtml, '<tr>');
		    }
		    push(@simplehtml, '<td style="vertical-align: top">');
		    push(@simplehtml, '<!-- ' . $key .  ' -->');
		    push (@simplehtml, $datumreportsimple{$key});
		    push(@simplehtml, '</td>');
		    if ($alt == 0) {
			$alt = 1;
		    }
		    else {
			$alt = 0;
			push(@simplehtml, '</tr>');
		    }
		}
	    }
	    push(@simplehtml, '</table>');
	}
	push (@finalhtml, '<hr>Color scale: <table style="max-width:50%"><tr><th>Color<th>Meaning<th>Impact</tr>'
	    , '<tr><td><div style="color:green">Green</div><td>0% packet loss<td>Network working smoothly</tr>'
	    , '<tr><td><div style="color:orange">Orange</div><td>More than 0% and less than 1% packet loss<td>Possible some slight lag</tr>'
	    , '<tr><td><div style="color:red">Red</div><td>More than 1% and less than 100% packet loss<td>Likely this will create significant lag</tr>'
	    , '<tr><td><div style="color:black">Black</div><td>100% packet loss - could be site down or complete network disconnect or network blocked<td>If the site is still reachable for normal use, then this indicates a blocking or configuration error.</tr>'
	    , '</table>'
	    , '<hr>Note about netlength: this is half of the distance light could travel in a vacuum during the fastest ping time. ' 
	      . "Since the packets travel via a mix of copper as electrical impules and fiber as light pulses for the majority of their travel distance, "
	      . "thier flighttime will always be slower than speed of light through a vacuum. Additionally, routing and switching equipment will always "
	      . "impose a significant overhead, so the netlength is only a very crude measurement."
	      . "For reference, Google Maps shows a driving distance from CM to Chandler of 2633miles or 4237km, and an estimate of travel time at highway speeds of 41hrs." 
	    
	);
	push (@finalhtml, '</body></html>');
	push (@simplehtml, '<hr>Color scale: <table style="max-width:50%"><tr><th>Color<th>Meaning<th>Impact</tr>'
	    , '<tr><td><div style="color:green">Green</div><td>0% packet loss<td>Network working smoothly</tr>'
	    , '<tr><td><div style="color:orange">Orange</div><td>More than 0% and less than 1% packet loss<td>Possible some slight lag</tr>'
	    , '<tr><td><div style="color:red">Red</div><td>More than 1% and less than 100% packet loss<td>Likely this will create significant lag</tr>'
	    , '<tr><td><div style="color:black">Black</div><td>100% packet loss - could be site down or complete network disconnect or network blocked<td>If the site is still reachable for normal use, then this indicates a blocking or configuration error.</tr>'
	    , '</table>'
	);
	push (@simplehtml, '<a href="https://helpdesk.nnenews.com/status/details.html">More technical details</a> are available if needed.');
	push (@simplehtml, '</body></html>');
    }
    else {
	logmsg("Unable to open datadirectory '$datadir', aborting.\n",1);
    }
}
else {
    logmsg("Specified Datadirectory '$datadir' is not a directory, aborting.\n",1); 
}


sub logmsg($$) {
    my $msg = shift;
    my $die = shift;
    push(@finalhtml, $msg);
    if ($die == 1) {
	finalize_html();
	die $msg;
    }
}

sub finalize_html() {
    $html_finalized = 1;
    if (open(HTML, '>'.$htmlfile)) {
	print HTML join("\n", @finalhtml);
	close(HTML);
	if (open(HTML, '>' . $simplehtmlfile)) {
	    print HTML '<html><title>NNE Network Status</title><body>' . "\n";
	    print HTML 'This report <a href="https://helpdesk.nnenews.com/status/"><b>https://helpdesk.nnenews.com/status/</b></a> generated starting at ' . $reporthumantime . ". This report is updated every five minutes.\n";
	    print HTML '<table border="1" style="border:none;border-collapse:collapse">';
	    print HTML join("\n", sort {substr($a, index($a, '>' ,15 )) cmp substr($b, index($b, '>', 15))} @simplesummary);
	    print HTML '</table><p>';
	    print HTML join("\n", @simplehtml);
	    close(HTML);
	}
	my $year = $reporttime[5] + 1900;
	my $month = $reporttime[4] + 1;
	my $day = $reporttime[3];
	my $hour = $reporttime[2];
	my $mypath = File::Spec->catdir($htmlpath, $year);
	unless (-d $mypath) {
	    mkdir $mypath;	    
	}
	$mypath = File::Spec->catdir($mypath, $month);
	unless (-d $mypath) {
	    mkdir $mypath;
	}
	$mypath = File::Spec->catdir($mypath, $day);
	unless (-d $mypath) {
	    mkdir $mypath;
	}
	if (-d $mypath) {
	    copy($htmlfile, File::Spec->catfile($mypath, $hour . '.html'));
	}	
    }
    else {
	die "Unable to open $htmlpath for writing, aborting\n";
    }
}

my %datumstats; 
my %bins;
my %rawsamples; 

sub process_datum($) {
    my $datum = shift;   
    %datumstats = ();
    my @datumsamples;
    my @minorlist;
    my @minordetaillist;
    my @minordev;
    my @majorlist;
    my @majordetaillist;
    my @majordev;
    my @minorsamples;
    my @majorsamples;
    my $laststart;
    my $firststart;
    if (opendir(DATUM, $datum)) {
	my $techopen = '<!-- <div style="color:Gainsboro;font-size:x-small">';
	my $techclose = '</div> -->';
	my $techdetails = $techopen;
	$techdetails .= '<br>datum path: ' . $datum . "\n";
	%bins = ();
	$techdetails .= '<br>bin keys: ' . join(':', keys %bins) . "\n";
	$laststart = 0;
	my $ent;
	while($ent = readdir(DATUM)) {
	    my $filename = File::Spec->catfile($datum, $ent);
	    if (-f $filename) {
		unless ($ent =~ m/\D/) {
		    my @filestats = stat($filename);
		    if ($filestats[9] > $datumcutofftime) {
			process_file($datum, $filename, $filestats[9]);
		    }
		    else {
			# silently ignore files older than the cutoff time
		    }
		}
		else {
		    # silently ignore files with non-digits in the name
		}
	    }
	    else {
		# silently ignore nonfiles
	    }
	}
	closedir(DATUM);
	

	my $i = $reportstarttime;
	@minorlist = ();
	@minordetaillist = ();
	@minorsamples = ();       
	@minordev = ();       
	
	while($i > $datumcutofftime) {
	    my $thistrans = 0;
	    my $thisrecv = 0;
	    my $firststart = undef;
	    my $laststart = undef;
	    my $start;
	    foreach $start (keys %bins) {
		if ((($i - 300) lt $start) && ($start lt $i)) {
		    my $atrans;
		    my $arecv;
		    ($atrans, $arecv) = split(':', $bins{$start});
		    @minorsamples = split(':', $rawsamples{$start});
		    $techdetails .= '<br>Ping times for ' . $start . '=' . $rawsamples{$start} . "\n" ;
		    push(@datumsamples, @minorsamples);
		    $thistrans += $atrans;
		    $thisrecv += $arecv;
		    if ($firststart) {
			if ($firststart gt $start) {
			    $firststart = $start;
			}
		    }
		    else {
			$firststart = $start;
		    }
		    if ($laststart) {
			if ($laststart lt $start) {
			    $laststart = $start;
			}
		    }
		    else {
			$laststart = $start;
		    }
		}
	    }
	    $firststart = $reportstarttime - $firststart;
	    $laststart = $reportstarttime - $laststart;
	    if ($thistrans == 0) {
		$techdetails .= '<br>minor setting to n/a' . "\n";
		push(@minorlist, 'n/a'); 
		push(@minordetaillist, 'n/a'); 
		push(@minordev, 'n/a');
	    }
	    else {
		my $loss = ($thistrans - $thisrecv) / $thistrans * 100;
		my $stddev = stddev(@minorsamples);
		push(@minordetaillist, sprintf("(%d - %d) / %d * 100 = %.2f%% <br> %d lost packets <br> [ %d - %d ] \n", $thistrans, $thisrecv, $thistrans, $loss, $thistrans - $thisrecv, $laststart, $firststart));
		$techdetails .= '<br>minor stddev(' . join(',', @minorsamples) . ') =' . $stddev . "\n";
		push(@minorlist, sprintf("%.2f", $loss));
		push(@minordev, $stddev);
	    }
	    $i -= 300;
	}
	$i = $reportstarttime;
	@majorlist = ();
	@majordetaillist = ();
	@majorsamples = ();       
	@majordev = ();       
	while($i > $datumcutofftime) {
	    my $thistrans = 0;
	    my $thisrecv = 0;
	    my $firststart = undef;
	    my $laststart = undef;
	    my $start;
	    foreach $start (keys %bins) {
		if ((($i - 900) lt $start) && ($start lt $i)) {
		    my $atrans;
		    my $arecv;
		    ($atrans, $arecv) = split(':', $bins{$start});
		    @majorsamples = split(':', $rawsamples{$start});
		    $thistrans += $atrans;
		    $thisrecv += $arecv;
		    if ($firststart) {
			if ($firststart gt $start) {
			    $firststart = $start;
			}
		    }
		    else {
			$firststart = $start;
		    }
		    if ($laststart) {
			if ($laststart lt $start) {
			    $laststart = $start;
			}
		    }
		    else {
			$laststart = $start;
		    }
		}
	    }
	    $firststart = $reportstarttime - $firststart;
	    $laststart = $reportstarttime - $laststart;
	    if ($thistrans == 0) {
		$techdetails .= '<br>major setting to n/a' . "\n";
		push(@majorlist, 'n/a'); 
		push(@majordev, 'n/a');
	    }
	    else {
		my $loss = ($thistrans - $thisrecv) / $thistrans * 100;
		my $stddev = stddev(@majorsamples);
		push(@majordetaillist, sprintf("(%d - %d) / %d * 100 = %.2f%% <br> %d lost packets <br> [ %d - %d ] \n", $thistrans, $thisrecv, $thistrans, $loss, $thistrans - $thisrecv, $laststart, $firststart));
		$techdetails .= '<br>major stddev(' . join(',', @majorsamples) . ') =' . $stddev . "\n";
		push(@majorlist, sprintf("%.2f", $loss));
		push(@majordev, $stddev);
	    }
	    $i -= 900;
	}
	{
	    my $datumstddev = stddev(@datumsamples);
	    my $breakdowntable = '<br><div style="margin: 10px">'
	      . '<table border="1" style="border:none;border-collapse:collapse"><tr align="center"><td>Minutes Ago<td>0<td>5<td>10<td>15<td>20<td>25<td>30<td>35<td>40<td>45<td>50<td>55</tr>'
	      . '<tr align="center"><td>Loss as %<td>' . join('<td>', @minorlist) . '</tr>'
	      . '<tr align="center"><td>Jitter/Std Dev<td>' . join('<td>', @minordev) . '</tr>'
	      . '<tr align="center"><td>Loss as %<td colspan="3">' . join('<td colspan="3">' , @majorlist) . '</tr>'
	      . '<tr align="center"><td>Jitter/Std Dev<td colspan="3">' . join('<td colspan="3">' , @majordev) . '</tr>'
	      . '</table>For all numbers, smaller is better</div>';
	    my $detailbreakdowntable = '<br><div style="margin: 10px">'
	      . '<table border="1" style="border:none;border-collapse:collapse"><tr align="center"><td>Minutes Ago<td>0<td>5<td>10<td>15<td>20<td>25<td>30<td>35<td>40<td>45<td>50<td>55</tr>'
	      . '<tr align="center"><td>Loss<br>[Age range in s]<td>' . join('<td>', @minordetaillist) . '</tr>'
	      . '<tr align="center"><td>Jitter/Std Dev<td>' . join('<td>', @minordev) . '</tr>'
	      . '<tr align="center"><td>Loss<br>[Age range in s]<td colspan="3">' . join('<td colspan="3">' , @majordetaillist) . '</tr>'
	      . '<tr align="center"><td>Jitter/Std Dev<td colspan="3">' . join('<td colspan="3">' , @majordev) . '</tr>'
	      . '<tr align="center"><td>Loss<td colspan="12">' . sprintf('%.3f%%' , ($datumstats{'overall_ploss'} * 100 )) . '<br>' . ($datumstats{'ptranstotal'} - $datumstats{'precvtotal'}) . ' lost packets</tr>'  
	      . '<tr align="center"><td>Jitter/Std Dev<td colspan="12">' . $datumstddev . '</tr>'
	      . '</table></div>';

	    my $displaydesc;
	    
	    if ($datumstats{'overall_ploss'} == 0) {	    
		$displaydesc = '<div style="color:green;font-size:x-large">';
		$breakdowntable = '<br><div style="margin: 10px">'
		  . '<table border="1" style="border:none;border-collapse:collapse"><tr align="center"><td>Minutes Ago<td>0<td>5<td>10<td>15<td>20<td>25<td>30<td>35<td>40<td>45<td>50<td>55</tr>'
		  . '<tr align="center"><td>Jitter/Std Dev<td>' . join('<td>', @minordev) . '</tr>'
		  . '<tr align="center"><td>Jitter/Std Dev<td colspan="3">' . $majordev[0] . '<td colspan="3">' . $majordev[1] . '<td colspan="3">' . $majordev[2] . '<td colspan="3">' . $majordev[3] . '</tr>'
		  . '</table>For all numbers, smaller is better</div>';
		$detailbreakdowntable = $breakdowntable;
	    }
	    elsif ($datumstats{'overall_ploss'} < 0.01) {
		$displaydesc = '<div style="color:orange;font-size:x-large">';
	    }
	    elsif ($datumstats{'overall_ploss'} < 1) {
		$displaydesc = '<div style="color:red;font-size:x-large">';
	    }
	    else {
		$displaydesc = '<div style="font-size:x-large">';
	    }
	    $displaydesc .= $datumstats{'description'} . '</div>';
	    
	    $techdetails .= $techclose;
	    my $numberformatter = new Number::Format;
	    $datumreports{$datumstats{'description'}} = join("\n" 
		, '<hr>' . $displaydesc 		
		, sprintf('<br>Overall packet loss: <b>%.3f%%</b>' , ($datumstats{'overall_ploss'} * 100 ))  
		, '<br>Overall jitter (smaller is better): ' . $datumstddev
		, '<br>Tests completed in the last hour (60 is nominal. 59 or 61 is acceptable time quantization error, outside of that is a problem with reporting station): ' . $datumstats{'pingtests_considered'}
		, '<br>Target: ' . $datumstats{'target'} 
		, '<br>Total packet sent: ' . $datumstats{'ptranstotal'}
		, '<br>Total packets received: ' . $datumstats{'precvtotal'}	
		, sprintf('<br>Average ping time (ms): %.2f' , ($datumstats{'rttavgaccum'} / $datumstats{'pingtests_considered'} ) )
		, sprintf('<br>Fastest ping time (ms): %.2f' , $datumstats{'rttmin'} )
		, '<br>netlength (km): ', $numberformatter->format_number((299792 * $datumstats{'rttmin'} / 2 / 1000), 1) 
		, $detailbreakdowntable
		, $techdetails
		, '<br>Data files that go into this report can be found in ' . $datum . ' with a last modified time between ' . localtime($datumcutofftime) . ' and ' . localtime($reportstarttime) . ' (localtime)'
	    );
	    
	    unless ($datumstats{'description'} =~ /struct/g) {
		$datumreportsimple{$datumstats{'description'}} = join("\n" 
		    , $displaydesc 
		    , sprintf('<br>Overall packet loss: <b>%.3f%%</b>' , ($datumstats{'overall_ploss'} * 100 ))  
		    , '<br>Overall jitter (smaller is better): ' . $datumstddev
		    , sprintf('<br>Average ping time (ms): %.2f' , ($datumstats{'rttavgaccum'} / $datumstats{'pingtests_considered'} ) )
		    , '<br>Tests completed in the last hour (between 59-61 is ok, outside of that is a problem): ' . $datumstats{'pingtests_considered'}		    
		    , $breakdowntable
		);
		push(@simplesummary, join("\n" 
		    , '<tr>'
		    , '<td>' . $displaydesc
		    , sprintf('<td>Loss: <b>%.3f%%</b>' , ($datumstats{'overall_ploss'} * 100 ))  
		    , '<td>Jitter: ' . $datumstddev
		    , '</tr>'
		    ));
	    }
	}
    }
    else {
	logmsg("process_datum: Error opening '$datum' as a directory,  skipping.\n",0);
    }
}

sub process_file($$) {
    my $datum = shift;
    my $file = shift;
    my $filemodtime = shift;
    if (open(FILE, $file)) {
	my $line;
	my $starttime ; 
	my $target ;
	my $description ;
	my $samples ;
	my $ptrans ;
	my $precv ;
	my $ploss ;
	my $ptime ;
	my $rttmin ;
	my $rttmax ;
	my $rttavg ;
	my $rttmdev ;
	my $stddev ;
	my $pingtimes ;

	while($line = <FILE>) {
	    $line =~ s/\s+\Z//;
	    if ($line =~ m/=/) {
		my $key;
		my $value;
		($key, $value) = split('=', $line);
		if (lc $key eq 'starttime') {
		    $starttime = $value; 
		}
		elsif (lc $key eq 'target') {
		    $target = $value;
		}
		elsif (lc $key eq 'description') {
		    $description = $value;
		}
		elsif (lc $key eq 'samples') {
		    $samples = $value;
		}
		elsif (lc $key eq 'ptrans') {
		    $ptrans = $value;
		}
		elsif (lc $key eq 'precv') {
		    $precv = $value;
		}
		elsif (lc $key eq 'ploss') {
		    $ploss = $value;
		}
		elsif (lc $key eq 'ptime') {
		    $ptime = $value;
		}
		elsif (lc $key eq 'rttmin') {
		    $rttmin = $value;
		}
		elsif (lc $key eq 'rttmax') {
		    $rttmax = $value;
		}
		elsif (lc $key eq 'rttavg') {
		    $rttavg = $value;
		}
		elsif (lc $key eq 'rttmdev') {
		    $rttmdev = $value;
		}
		elsif (lc $key eq 'stddev') {
		    $stddev = $value;
		}
		elsif (lc $key eq 'pingtimes') {
		    $pingtimes = $value;
		}
	    }
	}
	close(FILE);
	
	unless ($pingtimes =~ /\S/) {
	    push(@finalhtml, '<!-- For $file, pingtimes is empty. -->' . "\n");
	}
	
	push(@finalhtml, '<!-- set bins - ' . $filemodtime . ':' . $file . ' pt:' . $ptrans . ' pr:' . $precv . ' rawsamp:' . $pingtimes ."-->\n") ;
	$bins{$filemodtime} = $ptrans . ':' . $precv; 
	$rawsamples{$filemodtime} = $pingtimes;
	
	$datumstats{'description'} = $description;
	$datumstats{'target'} = $target;
	
	if (exists($datumstats{'pingtests_considered'})) {
	    $datumstats{'pingtests_considered'} += 1;
	}
	else {
	    $datumstats{'pingtests_considered'} = 1;
	}
	
	if (exists($datumstats{'rttmax'})) {
	    if ($datumstats{'rttmax'} < $rttmax) {
		$datumstats{'rttmax'} = $rttmax;		
	    }
	}
	else {
	    $datumstats{'rttmax'} = $rttmax;
	}
	
	if (exists($datumstats{'rttmin'})) {
	    if ($datumstats{'rttmin'} > $rttmin) {
		$datumstats{'rttmin'} = $rttmin;		
	    }
	}
	else {
	    $datumstats{'rttmin'} = $rttmin;
	}
	
	if (exists($datumstats{'rttavgaccum'})) {
	    $datumstats{'rttavgaccum'} += $rttavg;
	}
	else {
	    $datumstats{'rttavgaccum'} = $rttavg;
	}
	
	if (exists($datumstats{'ptranstotal'})) {
	    $datumstats{'ptranstotal'} += $ptrans;
	}
	else {
	    $datumstats{'ptranstotal'} = $ptrans;
	}
	
	if (exists($datumstats{'precvtotal'})) {
	    $datumstats{'precvtotal'} += $precv;
	}
	else {
	    $datumstats{'precvtotal'} = $precv;
	}
	
	$datumstats{'overall_ploss'} = ($datumstats{'ptranstotal'} - $datumstats{'precvtotal'}) / $datumstats{'ptranstotal'}
	
    }	
    else {
	logmsg("Error opening '$file', skipping.\n", 0);
    }
}

if ($html_finalized == 0) {
    finalize_html();
}


    