#!/usr/bin/perl

=pod

=head1 NAME

ping_report.pl

=head1 DESCRIPTION

ping_report.pl is the third and final step of ping_logger. It gathers all 
reports that have come in and creates HTML summaries of them.

Two summaries are created, one with few details intended for general users,
another with full technical details intended for tech support staff. The
general summary is overwriten each time that ping_report.pl is run. The
detailed summary gets copied both to a fixed name as well as an hour based
filename so that an archive of the hourly ones is built up over time.

=head1 DEPENDANCIES

ping_report.pl requires the following modules to already be in the local 
Perl install:
    
=over 

=item Template

=item Statistics::Basic

=item File::Spec

=item File::Copy

=item Number::Format

=item XML::Twig

=item Compress::Bzip2

=back

=cut

use strict;

use Template;
use File::Spec;
use File::Copy;
use Statistics::Basic qw(:all nofill);
use Number::Format;
use XML::Twig;
use Compress::Bzip2;

# Start of global variable definitions

my $configfile = "/etc/ping_report.conf";

my $html_finalized = 0;
my $reportstarttime = time;
my $timerange = 3600;
my $reporthumantime = localtime($reportstarttime);
my @reporttime = localtime($reportstarttime);

my @finalhtml;
my @simplehtml;
my @simplesummary;

# datumstats holds the pieces that will go into "site"
my $datumstats;
my $description;
my $siteurl;
my $sitename;

my $datadir = "/var/pinglogger/";
my $simplehtmlfilename = "index.html";
my $htmlfilename = "details.html";
my $htmlpath = "/var/www/status/";

my %datumreports;
my %datumreportsimple;

# next two use the file modification time as the key
# bins holds precv and psent for every sample reported from ping_test
my %bins;
# rawsamples holds the rtt of all pings returned from ping_test
my %rawsamples; 

my $htmlfile;
my $simplehtmlfile;
my $datumcutofftime;
my $simpletemplate;
my $detailtemplate;

my $ttvars = {};

# No more global variables should be declared beyond here

# Start of subroutine definitions

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
    
=pod 

=head1 TEMPLATE VARIABLES

Template files use Template::Toolkit (see http://template-toolkit.org )

The following variables are available for a template to use:
    
=over

=item I<sites> a description sorted array of I<site>. I<site> is the 
summary of data for the entire hour for a given source.

=item I<site.style> = CSS style for the header for this site, this is where
the color coding comes into play. Style names are 'unreach', 'normal', 
'warn' and 'error'

=item I<site.description> = Description of this site

=item I<site.plosspercent> = Percentage of packets lost for this site, 
includes percent sign

=item I<site.jitter> = Jitter for this site

=item I<site.tests> = The number of report files found in the hour, i.e. the 
number of times that ping_test.pl successfully logged a sample through
ping_logger.pl

=item I<site.target> = The remote host that was pinged

=item I<site.packets_sent> = The total ping packet sent to the target

=item I<site.packets_recv> = The number of packets received back in the hour

=item I<site.rttavg> = Average round trip time of packets received

=item I<site.rttmin> = Shortest round trip time of packets received

=item I<site.netlength> = 1/2 rttmin/speed of light

=item I<site.ploss> = The number of packets lost in the hour (difference 
between I<site.packets_sent> and I<site.packets_recv>)

=item I<site.datadir> = Full path to site specific directory where results are
stored

=item I<site.firsttime> = Earliest timestamp on a report file that goes into 
the results

=item I<site.lasttime> = Latest timestamp on a report file that goes into the 
results

=item I<minors> = time sorted array of smallest summarized units (baseline
5min increments)

=item I<minor.age> = age in minutes of the most recent sample in minor rounded 
to 5 minute buckets

=item I<minor.psent> = packets sent within the minor

=item I<minor.precv> = packets received within the minor

=item I<minor.jitter> = jitter within the minor

=item I<minor.plosspercent> = packet loss as percent within the minor, including
sign

=item I<minor.ploss> = packet loss within the minor in units of packets

=item I<minor.startage> = actual earliest timestamp in seconds ago

=item I<minor.endage> = actual latest timestamp in seconds ago

=item I<majors = time sorted array of larger summarized units (baseline 
15min increments) same variables as minors, but for 15min range instead
of 5min range. Additionally one more variable is available in major: 

=item I<major.factor> = the number of minor samples that go into each major
so for 5min/15min, the factor = 3
    
=back

=head1 TIMEFRAMES

There are assumptions about timeframes built into the scripts and 
configurations at NNE - that the
reporting window is the past hour, that the archive of detailed scripts is 
stored by days, that the minor time frame is 5 minutes, that the major time
frame is 15 minutes.

=cut

    my $simpletemplate = Template->new();
    if ($simpletemplate->process($detailtemplate, $ttvars, $htmlfile)) {
    #if (open(HTML, '>'.$htmlfile)) {
    #	print HTML join("\n", @finalhtml);
    #	close(HTML);
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


sub process_datum($) {
    my $datum = shift;   
    $datumstats = {};
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
    	
    	# Read all the files 
    	my $ent;
    	while($ent = readdir(DATUM)) {
    	    my $filename = File::Spec->catfile($datum, $ent);
    	    if (-f $filename) {
        		if ($ent =~ m/\d+\.xml/) {
        		    my @filestats = stat($filename);
                    # TODO we should be testing for a time range, not just 
                    # 'newer than cutoff' 
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
    	
    	
        
        # Populate the minor list	
    	my $i = $reportstarttime;
    	@minorlist = ();
    	@minordetaillist = ();
    	@minorsamples = ();       
    	@minordev = ();       
    	
    	while($i > $datumcutofftime) {
    	    my $minorstats;
    	    my $thistrans = 0;
    	    my $thisrecv = 0;
    	    my $firststart = undef;
    	    my $laststart = undef;
    	    my $start;
    	    $minorstats = {};
    	    foreach $start (keys %bins) {
    		if ((($i - 300) lt $start) && ($start lt $i)) {
    		    my $atrans;
    		    my $arecv;
    		    ($atrans, $arecv) = split(':', $bins{$start});
    		    @minorsamples = split(':', $rawsamples{$start});
    		    $techdetails .= '<br>Ping times for ' . $start . '=' 
    		                    . $rawsamples{$start} . "\n" ;
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
        		$minorstats->{'list'} = 'n/a';
        		$minorstats->{'detaillist'} = 'n/a';
        		$minorstats->{'jitter'} = 'n/a';
    	    }
    	    else {
        		my $loss = ($thistrans - $thisrecv) / $thistrans * 100;
        		my $stddev = scalar stddev(@minorsamples);
        		$minorstats->{'list'} = sprintf("%.2f", $loss);
        		$minorstats->{'ptrans'} = $thistrans;
        		$minorstats->{'precv'} = $thisrecv;
        		$minorstats->{'plosspercent'} = sprintf("%.2f%%", $loss);
        		$minorstats->{'ploss'} = $thistrans - $thisrecv;
        		$minorstats->{'laststart'} = $laststart;
        		$minorstats->{'firststart'} = $firststart;
        		$minorstats->{'jitter'} = $stddev;
        		push(@minordetaillist, sprintf("(%d - %d) / %d * 100 = %.2f%% <br> %d lost packets <br> [ %d - %d ] \n", $thistrans, $thisrecv, $thistrans, $loss, $thistrans - $thisrecv, $laststart, $firststart));
        		$techdetails .= '<br>minor stddev(' . join(',', @minorsamples) . ') =' . $stddev . "\n";
        		push(@minorlist, sprintf("%.2f", $loss));
        		push(@minordev, $stddev);
    	    }
    	    $i -= 300;
            push (@{$datumstats->{'minors'}}, $minorstats);
    	}
    	
    	# Populate the major list
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
        		my $stddev = scalar stddev(@majorsamples);
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
    	      . '<tr align="center"><td>Loss<td colspan="12">' . sprintf('%.3f%%' , ($datumstats->{'overall_ploss'} * 100 )) . '<br>' . ($datumstats->{'ptranstotal'} - $datumstats->{'precvtotal'}) . ' lost packets</tr>'  
    	      . '<tr align="center"><td>Jitter/Std Dev<td colspan="12">' . $datumstddev . '</tr>'
    	      . '</table></div>';
    
    	    my $displaydesc;
    	    
    	    if ($datumstats->{'overall_ploss'} == 0) {	    
    		$displaydesc = '<div style="color:green;font-size:x-large">';
    		$breakdowntable = '<br><div style="margin: 10px">'
    		  . '<table border="1" style="border:none;border-collapse:collapse"><tr align="center"><td>Minutes Ago<td>0<td>5<td>10<td>15<td>20<td>25<td>30<td>35<td>40<td>45<td>50<td>55</tr>'
    		  . '<tr align="center"><td>Jitter/Std Dev<td>' . join('<td>', @minordev) . '</tr>'
    		  . '<tr align="center"><td>Jitter/Std Dev<td colspan="3">' . $majordev[0] . '<td colspan="3">' . $majordev[1] . '<td colspan="3">' . $majordev[2] . '<td colspan="3">' . $majordev[3] . '</tr>'
    		  . '</table>For all numbers, smaller is better</div>';
    		$detailbreakdowntable = $breakdowntable;
    	    }
    	    elsif ($datumstats->{'overall_ploss'} < 0.01) {
    		$displaydesc = '<div style="color:orange;font-size:x-large">';
    	    }
    	    elsif ($datumstats->{'overall_ploss'} < 1) {
    		$displaydesc = '<div style="color:red;font-size:x-large">';
    	    }
    	    else {
    		$displaydesc = '<div style="font-size:x-large">';
    	    }
    	    $displaydesc .= $datumstats->{'description'} . '</div>';
    	    
    	    $techdetails .= $techclose;
    	    my $numberformatter = new Number::Format;
    	    $datumreports{$datumstats->{'description'}} = join("\n" 
    		, '<hr>' . $displaydesc 		
    		, sprintf('<br>Overall packet loss: <b>%.3f%%</b>' , ($datumstats->{'overall_ploss'} * 100 ))  
    		, '<br>Overall jitter (smaller is better): ' . $datumstddev
    		, '<br>Tests completed in the last hour (60 is nominal. 59 or 61 is acceptable time quantization error, outside of that is a problem with reporting station): ' . $datumstats->{'pingtests_considered'}
    		, '<br>Target: ' . $datumstats->{'target'} 
    		, '<br>Total packet sent: ' . $datumstats->{'ptranstotal'}
    		, '<br>Total packets received: ' . $datumstats->{'precvtotal'}	
    		, sprintf('<br>Average ping time (ms): %.2f' , ($datumstats->{'rttavgaccum'} / $datumstats->{'pingtests_considered'} ) )
    		, sprintf('<br>Fastest ping time (ms): %.2f' , $datumstats->{'rttmin'} )
    		, '<br>netlength (km): ', $numberformatter->format_number((299792 * $datumstats->{'rttmin'} / 2 / 1000), 1) 
    		, $detailbreakdowntable
    		, $techdetails
    		, '<br>Data files that go into this report can be found in ' . $datum . ' with a last modified time between ' . localtime($datumcutofftime) . ' and ' . localtime($reportstarttime) . ' (localtime)'
    	    );
    	    
    	    unless ($datumstats->{'description'} =~ /struct/g) {
    		$datumreportsimple{$datumstats->{'description'}} = join("\n" 
    		    , $displaydesc 
    		    , sprintf('<br>Overall packet loss: <b>%.3f%%</b>' , ($datumstats->{'overall_ploss'} * 100 ))  
    		    , '<br>Overall jitter (smaller is better): ' . $datumstddev
    		    , sprintf('<br>Average ping time (ms): %.2f' , ($datumstats->{'rttavgaccum'} / $datumstats->{'pingtests_considered'} ) )
    		    , '<br>Tests completed in the last hour (between 59-61 is ok, outside of that is a problem): ' . $datumstats->{'pingtests_considered'}		    
    		    , $breakdowntable
    		);
    		push(@simplesummary, join("\n" 
    		    , '<tr>'
    		    , '<td>' . $displaydesc
    		    , sprintf('<td>Loss: <b>%.3f%%</b>' , ($datumstats->{'overall_ploss'} * 100 ))  
    		    , '<td>Jitter: ' . $datumstddev
    		    , '</tr>'
    		    ));
    	    }
    	}
	    push (@{$ttvars->{'sites'}}, $datumstats);
    }
    else {
	logmsg("process_datum: Error opening '$datum' as a directory,  skipping.\n",0);
    }
}

sub process_file($$) {
    my $datum = shift;
    my $file = shift;
    my $filemodtime = shift;
    my $twig = XML::Twig->new();
    if ($twig->safe_parsefile($file)) {
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
    	
    	my $root;
    	$root = $twig->root;
    	{
    	    my $version = $root->first_child_text('FormatVersion');
    	    if ($version != 2) {
    	        logmsg("File '$file' not in Format Version 2, skipping.\n", 0);
    	        return;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Starttime');
	        $starttime = $value;
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Target');
	        $target = $value;
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Description');
	        $description = $value;
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Samples');
    	    unless ($value =~ /\D/) {
    	        $samples = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Ptrans');
    	    unless ($value =~ /\D/) {
    	        $ptrans = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Precv');
    	    unless ($value =~ /\D/) {
    	        $precv = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Ploss');
    	    unless ($value =~ /\D/) {
    	        $ploss = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Ptime');
    	    unless ($value =~ /\D/) {
    	        $ptime = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttmin');
    	    unless ($value =~ /\D/) {
    	        $rttmin = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttmax');
    	    unless ($value =~ /\D/) {
    	        $rttmax = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttavg');
    	    unless ($value =~ /\D/) {
    	        $rttavg = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttmdev');
    	    unless ($value =~ /\D/) {
    	        $rttmdev = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Stddev');
    	    unless ($value =~ /\D/) {
    	        $stddev = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    my $timesample;
    	    my @these_times;
    	    my $pingtime_element = $root->first_child('Pingtimes');
    	    foreach $timesample ($pingtime_element->children('Time')) {
    	        push(@these_times, $timesample->text());
    	    }   
    	    $pingtimes = join(':', @these_times);
    	}
    
    	unless ($pingtimes =~ /\S/) {
    	    push(@finalhtml, '<!-- For $file, <Pingtimes> is empty. -->' . "\n");
    	}
    	
    	push(@finalhtml, '<!-- set bins - ' . $filemodtime . ':' . $file . ' pt:' . $ptrans . ' pr:' . $precv . ' rawsamp:' . $pingtimes ."-->\n") ;
    	$bins{$filemodtime} = $ptrans . ':' . $precv; 
    	$rawsamples{$filemodtime} = $pingtimes;
    	
    	$datumstats->{'description'} = $description;
    	$datumstats->{'target'} = $target;
    	
    	if (exists($datumstats->{'pingtests_considered'})) {
    	    $datumstats->{'pingtests_considered'} += 1;
    	}
    	else {
    	    $datumstats->{'pingtests_considered'} = 1;
    	}
    	
    	if (exists($datumstats->{'rttmax'})) {
    	    if ($datumstats->{'rttmax'} < $rttmax) {
    		$datumstats->{'rttmax'} = $rttmax;		
    	    }
    	}
    	else {
    	    $datumstats->{'rttmax'} = $rttmax;
    	}
    	
    	if (exists($datumstats->{'rttmin'})) {
    	    if ($datumstats->{'rttmin'} > $rttmin) {
    		$datumstats->{'rttmin'} = $rttmin;		
    	    }
    	}
    	else {
    	    $datumstats->{'rttmin'} = $rttmin;
    	}
    	
    	if (exists($datumstats->{'rttavgaccum'})) {
    	    $datumstats->{'rttavgaccum'} += $rttavg;
    	}
    	else {
    	    $datumstats->{'rttavgaccum'} = $rttavg;
    	}
    	
    	if (exists($datumstats->{'ptranstotal'})) {
    	    $datumstats->{'ptranstotal'} += $ptrans;
    	}
    	else {
    	    $datumstats->{'ptranstotal'} = $ptrans;
    	}
    	
    	if (exists($datumstats->{'precvtotal'})) {
    	    $datumstats->{'precvtotal'} += $precv;
    	}
    	else {
    	    $datumstats->{'precvtotal'} = $precv;
    	}
    	
    	$datumstats->{'overall_ploss'} = ($datumstats->{'ptranstotal'} - $datumstats->{'precvtotal'}) / $datumstats->{'ptranstotal'}
    	
    }	
    else {
	    logmsg("Error '" . $@ . "' when attempting to parse XML file '$file', skipping.\n", 0);
    }
}

# Start of global code

if ($ARGV[0]) {
  if (-f $ARGV[0]) {
    $configfile = $ARGV[0];
  }
  else {
      print "Config file specified on command line '" . $ARGV[0] 
      . "' not found as a file, trying to use default $configfile instead.\n";
  }
}

if (-f $configfile) {
    open(CONF, $ARGV[0]);
}
else {
    die "No configuration file '$configfile' found, aborting.\n";
}

{
    my $line;
    while($line = <CONF>) {
        $line =~ s/\#*\Z//;
        $line =~ s/\s\Z//;
        if ($line =~ m/=/) {
        	my $key;
        	my $value;
        	($key, $value) = split('=', $line, 2);
        	if (lc $key eq 'datadir') {
        	    if (-d $value) {
	                $datadir = $value;
        	    }
	        }
	        elsif (lc $key eq 'htmlpath') {
	            if (-d $value) {
	                $htmlpath = $value;
	            }
	        }
	        elsif (lc $key eq 'siteurl') {
	            $siteurl = $value;
	        }
	        elsif (lc $key eq 'sitename') {
	            $sitename = $value;
	        }
	        elsif (lc $key eq 'simplefile') {
	            $simplehtmlfilename = $value;
	        }
	        elsif (lc $key eq 'detailfile') {
	            $htmlfilename = $value;
	        }
	        elsif (lc $key eq 'simpletemplate') {
	            $simpletemplate = $value;
	        }
	        elsif (lc $key eq 'detailtemplate') {
	            $detailtemplate = $value;
	        }
	        elsif (lc $key eq 'timerange') {
	            unless ($value =~ /\D/) {
	                $timerange = $value;
	            }
	        }
        }
        else {
        	# No equal sign? Ignore the line
        }
    }
}
close(CONF);

$datumcutofftime = $reportstarttime - $timerange;
$simplehtmlfile = File::Spec->catfile($htmlpath, $simplehtmlfilename);
$htmlfile = File::Spec->catfile($htmlpath, $htmlfilename);

if (-d $datadir) {
    if (opendir(PARENT, $datadir)) {
	my @data;
	my $ent;
	push (@finalhtml, '<html><title>' . $sitename 
	    .  ' Network Status - Detail</title><body>');
	push (@finalhtml, 'This report <a href="' . $siteurl . $htmlfilename 
	    . '"><b>' . $siteurl . $htmlfilename . '</b></a> generated starting at ' 
	    . $reporthumantime . ". This report is updated every five minutes.\n");
	push (@finalhtml, '<p>See <a href="https://helpdesk.nnenews.com/projects' 
	    . '/nne/wiki/Pinglogger">Pinglogger wiki entry</a> in NNE helpdesk ' 
	    . ' for documentation (requires login).');
	{
	    my $year = $reporttime[5] + 1900;
	    my $month = $reporttime[4] + 1;
	    my $day = $reporttime[3];
	    my $hour = $reporttime[2];
	    my $url = sprintf($siteurl . '/%d/%d/%d/%d.html', $year, $month
	        , $day, $hour) ;	    
	    push (@finalhtml, '<p>For historic access to this report, see <a href="'
	        .$url . '">' . $url . '</a>');
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
	push (@simplehtml, '<a href="' . $siteurl . $htmlfilename . '">More technical details</a> are available if needed.');
	push (@simplehtml, '</body></html>');
    }
    else {
	logmsg("Unable to open datadirectory '$datadir', aborting.\n",1);
    }
}
else {
    logmsg("Specified Datadirectory '$datadir' is not a directory, aborting.\n",1); 
}


if ($html_finalized == 0) {
    finalize_html();
}

