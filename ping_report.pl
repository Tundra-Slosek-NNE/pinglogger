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

=item Scalr::Util

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
use Scalar::Util qw( looks_like_number );

# Start of global variable definitions

my $configfile = "/etc/ping_report.conf";

my $html_finalized = 0;
my $reportstarttime = time;
my $timerange = 3600;
my $minortime = 300;
my $majortime = 900;
my $reporthumantime = localtime($reportstarttime);
my @reporttime = localtime($reportstarttime);

# datumstats holds the pieces that will go into "site"
my $datumstats;
my $description;
my $siteurl;
my $sitename;

my $datadir = "/var/pinglogger/";
my $simplehtmlfilename = "index.html";
my $htmlfilename = "details.html";
my $htmlpath = "/var/www/status/";
my $templatepath;
my $keepdetailhistory = 1;

# next two use the file modification time as the key
# bins holds precv and ptrans for every sample reported from ping_test
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
    if ($die == 1) {
	finalize_html();
	die $msg;
    }
}

sub finalize_html() {
    $html_finalized = 1;
    my $detailarchivepath;
    my $hour;
=pod 

=head1 TEMPLATE VARIABLES

Template files use Template::Toolkit (see http://template-toolkit.org )

The following variables are available for a template to use:
    
=over

=item I<archpath> Will be omitted if keepdetailhistory is 'no'. If present, 
this will be the full URL to get to the persistent archive copy of the current
detail file.

=item I<archpathprev> Only present when I<archpath> is present. This is the 
calculated previous detail archive. If your I<timerange> is less than an hour, 
this will be wrong at least some of the time since it is based on the assumption 
of hour+ timerange; in this case don't use this variable in your templates.
Note that this does not assure that the URL points to an actual available file. 

=item I<archpathnext> Only present when I<archpath> is present. This is the 
calculated next detail archive. If your I<timerange> is less than an hour, 
this will be wrong at least some of the time since it is based on the assumption 
of hour+ timerange; in this case don't use this variable in your templates.
Note that this does not assure that the URL points to an actual available file. 

=item I<reporttime> Human formatted local time when the report was generated

=item I<sites> a description sorted array of I<site>. I<site> is the 
summary of data for the entire hour for a given source.

=item I<site.style> = CSS style for the header for this site, this is where
the color coding comes into play. Style names are 'unreach', 'normal', 
'warn' and 'error'

=item I<site.description> = Description of this site

=item I<site.plosspercent> = Percentage of packets lost for this site

=item I<site.jitter> = Jitter for this site

=item I<site.tests> = The number of report files found in the hour, i.e. the 
number of times that ping_test.pl successfully logged a sample through
ping_logger.pl

=item I<site.target> = The remote host that was pinged

=item I<site.ptrans> = The total ping packet sent to the target

=item I<site.precv> = The number of packets received back in the hour

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

=item I<minor.ptrans> = packets sent within the minor. Note that if 
no reports have been received by the logging host, then both the age and 
ptrans will be populated, but the other values will not be defined. Check 
that ptrans is greater than zero before relying on data in the other fields.

=item I<minor.precv> = packets received within the minor

=item I<minor.jitter> = jitter within the minor

=item I<minor.plosspercent> = packet loss as percent within the minor

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

    {
        $ttvars->{'reporttime'} = $reporthumantime;
    	my $year = $reporttime[5] + 1900;
    	my $month = $reporttime[4] + 1;
    	my $day = $reporttime[3];
    	$hour = $reporttime[2];
    	if ($keepdetailhistory == 1) {
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
        	    $detailarchivepath = $mypath;
        	}
        	$ttvars->{'archpath'} = $siteurl . '/' . $year . '/' . $month . '/'
        	    . $day . '/' . $hour . '.html';
            my @nextreporttime;
            @nextreporttime = localtime($reportstarttime + $timerange);
            $ttvars->{'archpathnext'} = $siteurl . '/' 
                . ($nextreporttime[5] + 1900) . '/' 
                . ($nextreporttime[4] + 1) . '/'
        	    . $nextreporttime[3] . '/'  
        	    . $nextreporttime[2] . '.html';
            my @prevreporttime;
            @prevreporttime = localtime($reportstarttime - $timerange);
            $ttvars->{'archpathprev'} = $siteurl . '/' 
                . ($prevreporttime[5] + 1900) . '/' 
                . ($prevreporttime[4] + 1) . '/'
        	    . $prevreporttime[3] . '/'  
        	    . $prevreporttime[2] . '.html';
    	}
    }  
    unless (-d $templatepath) {
        die "Template path '$templatepath' is not a directory, aborting.\n";
    }
    my $templateengine = Template->new({INCLUDE_PATH=>$templatepath});
    if ($templateengine->process($detailtemplate, $ttvars, $htmlfile)) {
        if ($templateengine->process($simpletemplate, $ttvars, $simplehtmlfile)) {
        }
        else {
            # If we can process the detail but not the simple, what should we do?
        }   
    	if ($keepdetailhistory == 1) {
    	    copy($htmlfile, File::Spec->catfile($detailarchivepath, $hour . '.html'));
        }
    }
    else {
	    die "Error processing template for writing to output file, aborting with error:\n" . $templateengine->error() . "\n";
    }
}


sub process_datum($) {
    my $datum = shift;   
    $datumstats = {};
    my @datumsamples;
    my @minorsamples;
    my @majorsamples;
    my $laststart;
    my $firststart;
    if (opendir(DATUM, $datum)) {
        $datumstats->{'datadir'} = $datum;
    	%bins = ();
    	$laststart = 0;
    	
    	# Read all the files 
        {
        	my $ent;
        	my $oldestfile;
        	my $newestfile;
        	while($ent = readdir(DATUM)) {
        	    my $filename = File::Spec->catfile($datum, $ent);
        	    if (-f $filename) {
            		if ($ent =~ m/\d+\.xml/) {
            		    my @filestats = stat($filename);
            		    if ( ($filestats[9] > $datumcutofftime) &&
            		         ($filestats[9] < $reportstarttime)
            		       ){
            		        if ($filestats[9] > $newestfile) {
            		            $newestfile = $filestats[9];
            		        }
            		        unless ($oldestfile) {
            		            $oldestfile = $filestats[9];
            		        }
            		        if ($oldestfile > $filestats[9]) {
            		            $oldestfile = $filestats[9];
            		        }   
                			process_file($datum, $filename, $filestats[9]);
            		    }
            		    else {
                			# silently ignore files older than the cutoff time
            		    }
            		}
            		else {
            		    # silently ignore files that don't look like ours
            		}
        	    }
        	    else {
        		# silently ignore nonfiles
        	    }
        	}
        	
        	$datumstats->{'firsttime'} = scalar localtime($oldestfile);
        	$datumstats->{'lasttime'} = scalar localtime($newestfile);
        }
    	closedir(DATUM);
        
        # Populate the minor list	
    	my $i = $reportstarttime;
    	my $thisage;
    	@minorsamples = ();       

    	$thisage = 0;
    	while($i > $datumcutofftime) {
    	    my $minorstats;
    	    my $thistrans = 0;
    	    my $thisrecv = 0;
    	    my $firststart = undef;
    	    my $laststart = undef;
    	    my $start;
    	    $minorstats = {};
    	    foreach $start (keys %bins) {
    		if ((($i - $minortime) lt $start) && ($start lt $i)) {
    		    my $atrans;
    		    my $arecv;
    		    ($atrans, $arecv) = split(':', $bins{$start});
    		    @minorsamples = split(':', $rawsamples{$start});
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
    	    $minorstats->{'age'} = $thisage;
    	    $minorstats->{'startage'} = $laststart;
    	    $minorstats->{'endage'} = $firststart;
    		$minorstats->{'ptrans'} = $thistrans;
    	    if ($thistrans == 0) {
    	    }
    	    else {
        		my $losspercent = ($thistrans - $thisrecv) / $thistrans * 100;
        		my $stddev = stddev(@minorsamples);
        		$minorstats->{'list'} = sprintf("%.2f", $losspercent);
        		$minorstats->{'precv'} = $thisrecv;
        		$minorstats->{'plosspercent'} = $losspercent;
        		$minorstats->{'ploss'} = $thistrans - $thisrecv;
        		$minorstats->{'laststart'} = $laststart;
        		$minorstats->{'firststart'} = $firststart;
        		$minorstats->{'jitter'} = (0 + $stddev);
    	    }
    	    $i -= $minortime;
            push (@{$datumstats->{'minors'}}, $minorstats);
            $thisage += int($minortime / 60) ;
    	}
    	
    	# Populate the major list
    	$i = $reportstarttime;
    	@majorsamples = ();       
    	$thisage = 0;
    	while($i > $datumcutofftime) {
    	    my $majorstats;
    	    my $thistrans = 0;
    	    my $thisrecv = 0;
    	    my $firststart = undef;
    	    my $laststart = undef;
    	    my $start;
    	    $majorstats = {};
    	    foreach $start (keys %bins) {
        		if ((($i - $majortime) lt $start) && ($start lt $i)) {
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
    	    $majorstats->{'age'} = $thisage;
    	    $majorstats->{'startage'} = $laststart;
    	    $majorstats->{'endage'} = $firststart;
    	    $majorstats->{'factor'} = $majortime / $minortime;
    		$majorstats->{'ptrans'} = $thistrans;
    	    if ($thistrans == 0) {
    	    }
    	    else {
        		my $losspercent = ($thistrans - $thisrecv) / $thistrans * 100;
        		my $stddev = stddev(@majorsamples);
        		$majorstats->{'list'} = sprintf("%.2f", $losspercent);
        		$majorstats->{'precv'} = $thisrecv;
        		$majorstats->{'plosspercent'} = $losspercent;
        		$majorstats->{'ploss'} = $thistrans - $thisrecv;
        		$majorstats->{'laststart'} = $laststart;
        		$majorstats->{'firststart'} = $firststart;
        		$majorstats->{'jitter'} = (0 + $stddev);
    	    }
    	    $i -= $majortime;
    	    
            push (@{$datumstats->{'majors'}}, $majorstats);
            $thisage += int($majortime / 60) ;
    	}
    	
    	{
    	    $datumstats->{'jitter'} = (0+stddev(@datumsamples));

# Start of code to determine style to display the current site in
    	    if ($datumstats->{'plosspercent'} == 0) {	    
        		$datumstats->{'style'} = 'normal';
    	    }
    	    elsif ($datumstats->{'plosspercent'} < 1) {
        		$datumstats->{'style'} = 'warn';
    	    }
    	    elsif ($datumstats->{'plosspercent'} < 100) {
        		$datumstats->{'style'} = 'error';
    	    }
    	    else {
        		$datumstats->{'style'} = 'unreach';
    	    }
# End of code to determine the style to display the current site in

    	    my $numberformatter = new Number::Format;
    	    $datumstats->{'netlength'} = $numberformatter->format_number((299792 * $datumstats->{'rttmin'} / 2 / 1000), 1);
    	    $datumstats->{'rttavg'} = $datumstats->{'rttavgaccum'} / $datumstats->{'pingtests_considered'}; 

    	    
    	    unless ($datumstats->{'description'} =~ /struct/g) {
    	        # TODO figure out how not to send structural items to simple 
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
    	    if (looks_like_number($value)) {
    	        $rttmin = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttmax');
    	    if (looks_like_number($value)) {
    	        $rttmax = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttavg');
    	    if (looks_like_number($value)) {
    	        $rttavg = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Rttmdev');
    	    if (looks_like_number($value)) {
    	        $rttmdev = $value;
    	    }  
    	}
    	{
    	    my $value;
    	    $value = $root->first_child_text('Stddev');
    	    if (looks_like_number($value)) {
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
    	
    	if (exists($datumstats->{'ptrans'})) {
    	    $datumstats->{'ptrans'} += $ptrans;
    	}
    	else {
    	    $datumstats->{'ptrans'} = $ptrans;
    	}
    	
    	if (exists($datumstats->{'precv'})) {
    	    $datumstats->{'precv'} += $precv;
    	}
    	else {
    	    $datumstats->{'precv'} = $precv;
    	}
    	
       	$datumstats->{'plosspercent'} =  ($datumstats->{'ptrans'} - $datumstats->{'precv'}) / $datumstats->{'ptrans'} * 100;
       	$datumstats->{'ploss'} = $datumstats->{'ptrans'} - $datumstats->{'precv'};

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

=pod

=head1 CONFIGURATION 

The following configuration variables are defined

=over

=item I<datadir> = parent of all data directories

=item I<htmlpath> = where to output html files

=item I<siteurl> = URL of the logging host when needed within an html file

=item I<sitename> = Name organization

=item I<simplefile> = name of the html file that will be output for 'simple' 
point of view

=item I<detailfile> = name of the html file that will be output for 'detail' 
point of view

=item I<simpletemplate> = name of the Template::Toolkit formatted template
file that will be used as the source for 'simple' point of view

=item I<detailtemplate> = name of the Template::Toolkit formatted template
file that will be used as the source for 'detail' point of view

=item I<timerange> = Number of seconds to report on (NNE uses 3600, ie 1hr)

=item I<minortime> = Number of seconds in a minor division (NNE uses 300, ie 
5min)

=item I<majortime> = Number of seconds in a major division (NNE uses 900, ie
15min)

=item I<templatepath> = The parent directory for the template files

=item I<keepdetailhistory> = A yes/no (defaults to yes) flag of if a copy of 
the detail HTML file should be made and stored by date

=back

ping_report.pl is not tested for the following cases: 

=over 

=item I<timerange> is not an integer multiple of I<majortime>. 

=item I<majortime> is not an integer multiple of I<minortime>.

=item I<timerange> is not larger than I<majortime>. 

=item I<majortime> is not larger than I<minortime>.

=back

=cut

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
	        elsif (lc $key eq 'templatepath') {
	            if (-d $value) {
	                $templatepath = $value;
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
	        elsif (lc $key eq 'keepdetailhistory') {
	            if (
	                (lc $value eq 'n') || 
	                (lc $value eq 'no') ||
	                ($value == 0) ||
	                (lc $value eq 'false')
	            ){
	                $keepdetailhistory = 0;
	            }
	        }
	        elsif (lc $key eq 'minortime') {
	            unless ($value =~ /\D/) {
	                $minortime = $value;
	            }
	        }
	        elsif (lc $key eq 'majortime') {
	            unless ($value =~ /\D/) {
	                $majortime = $value;
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

