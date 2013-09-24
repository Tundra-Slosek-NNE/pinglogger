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

$rawreport = memBunzip(decode_base64($ARGV[0]));

my $twig = XML::Twig->new();

unless ($twig->safe_parse($rawreport)) {
    die 'Unable to parse the report, aborting. Error from XML::Twig:' 
        . "\n" . $@; 
}


my $datadir = "/var/pinglogger/";

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
