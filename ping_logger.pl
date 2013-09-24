#!/usr/bin/perl

=pod

=head1 NAME

ping_logger.pl

=head1 DESCRIPTION

ping_logger.pl is the second step of ping_logger. It runs on the logging host
and stores the results from the testing hosts for later use by ping_report.pl.

ping_logger.pl takes the data from the command line in the form of Base64
encoded report and writes it to a data directory C</var/pinglogger/> that is
hard coded. Within the data directory, a subdirectory is dedicated to this
report named by the md5sum of the description within the report. If the
subdirectory doesn't yet exist it will be created. Each report submitted is
saved with the starttime within the report as the filename on the logging 
host.

The format of the data at the command line is XML that has been bzip2 
compressed and then base64 encoded. The decoded and bzip2 decompressed XML 
is what is stored in the data directory. 

=head1 HISTORICAL FORMAT

Verions 1 of the exchange data was used previously. It had no format version 
number in the file. It was line oriented key=value with the raw multiline
ping output packed into a single line by replacing the newlines with a 
string of three tilde characters (~~~). 

=head1 DEPENDANCIES

ping_logger.pl requires the following modules to already be in the local 
Perl install:
    
=over 

=item MIME::Base64

=item Digest::MD5

=item File::Spec

=item XML::Twig

=item Compress::Bzip2

=back

=cut

use strict;
use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use File::Spec;
use XML::Twig;
use Compress::Bzip2;

my $rawreport;

my $configfile;
my $encoded;

unless ($ARGV[0]) {
    die "Must at least supply a report in the first parameter. Aborting.\n";
}   

=pod

=head1 PARAMETERS

ping_logger.pl requires at least one parameter - the base64 encoded report.

If two parameters are given, they will be checked in order to see if they 
match a filename on the system. If either does, it will be treated as the
configuration file and the other will be treated as the encoded report. If
neither matches a filename on the system, then the first will be treated as the
report and the second will be silently discarded.

=head1 CONFIGURATION

=head2 Configuration parameter location

Configuration parameters will be read from whichever of the following files 
are found first. Once a file is found, no other sources are consulted for 
configuration:
    
=over

=item command line

=item ~/.pinglogger.conf

=item /etc/pinglogger.conf

=item hard coded values

=back

=head2 Configuration parameters

Configuration parameters only come from a configuration file. See above for
the location. Within the file, lines are read one by one in the order found 
in the file. For each line, anything from a pound sign (#) through to the end
of the line is discarded. The line is split on the first equal sign (=) found.
If no equal sign is found, the line is discarded.

The following configuration parameter keys are defined. Any other values found 
are discarded.

=over

=item datadir = The parent directory of all data written. If not specified, 
the default value C</var/pinglogger/> is used (see CPAN File::Spec catdir
for details of how this is handled in a cross platform way). When you supply
the entry, it is assumed that you know how to properly supply a directory name
locally.

=back

=cut

$encoded = $ARGV[0];

if ($ARGV[1]) {
    # Two parameters? Check to see if either is a valid file.
    if (-f $ARGV[0]) {
        $encoded = $ARGV[1];
        $configfile = $ARGV[0];
    }
    elsif (-f $ARGV[1]) {
        $configfile = $ARGV[1];
    }  
    else {
        # no config file specified and default of encoded in first param holds
    }   
}   
else {
    # no config file specified and default of encoded in first param holds
}   

unless ($configfile) {
    if (-f '~/.pinglogger.conf') {
        $configfile = '~/.pinglogger.conf';
    }  
    elsif (-f '/etc/pinglogger.conf') {
        $configfile = '/etc/pinglogger.conf';
    }   
}

$rawreport = memBunzip(decode_base64($encoded));

my $twig = XML::Twig->new();

unless ($twig->safe_parse($rawreport)) {
    die 'Unable to parse the report, aborting. Error from XML::Twig:' 
        . "\n" . $@; 
}

# Configfile variables
my $datadir;

if (-f $configfile) {
    unless(open(CONF, $configfile)) {
        die "Unable to open configuration file '$configfile', aborting\n";
    }   
    my $line;
    while ($line = <CONF>) {
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
        }
        else {
    	# No equal sign? Ignore the line
        }
    }
}
else {
    my $tentativedir = File::Spec->catdir('var', 'pinglogger');  
    if (-d $tentativedir) {
        $datadir = $tentativedir;
    }
    else {
        if ($datadir) {
            die "Supplied data directory name '$datadir' is not a directory, "
            . "aborting.\n";
        }
        else {
            die "No definition of data directory found, aborting.\n";
        }
    }   
}   

close(CONF);


my $formatversion = $twig->root->first_child_text('FormatVersion');

unless ($formatversion == 2) {
    die "Don't know how to handle format version '" . $formatversion 
        . "', aborting.\n";
}   

my $starttime = $twig->root->first_child_text('Starttime');
my $description = $twig->root->first_child_text('Description');

if ($starttime && $description) {
    my $dirname = File::Spec->catdir($datadir, md5_hex($description));
    unless (-d $dirname) {
    	mkdir $dirname;
    	unless (-d $dirname) {
    	    die "Unable to create directory $dirname, aborting.\n";
    	}
    }
    my $filename = File::Spec->catfile($dirname, $starttime);
    
    if (open(DATAFILE, '>' . $filename)) {
    	print DATAFILE $rawreport;
    	close(DATAFILE);
    }
    else {
    	print "Unable to open $filename for writing, aborting.\n";
    }
}
else {
    die "Required tags Starttime and Description not found, aborting.\n";
}
