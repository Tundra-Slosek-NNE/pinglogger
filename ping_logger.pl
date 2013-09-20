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

=head1 DEPENDANCIES

ping_logger.pl requires the following modules to already be in the local 
Perl install:
    
=over 

=item MIME::Base64

=item Digest::MD5

=item File::Spec

=back

=cut


use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use File::Spec;

$rawreport = decode_base64($ARGV[0]);

$datadir = "/var/pinglogger/";

foreach $line (split("\n", $rawreport)) {
    $line =~ s/\s+\Z//;
    if ($line =~ m/\=/) {
	my $key;
	my $value;
	($key, $value) = split('=', $line, 2);
	if (lc $key eq 'starttime') {
	    unless ($value =~ m/\D/) {
		$starttime = $value;
	    }
	}
	elsif (lc $key eq 'description') {
	    $description = $value;
	}
	
    }
    else {
	# silently discard lines without an equal sign
    }
}

if ($starttime && $description) {
    $dirname = File::Spec->catdir($datadir, md5_hex($description));
    unless (-d $dirname) {
	mkdir $dirname;
	unless (-d $dirname) {
	    die "Unable to create directory $dirname, aborting.\n";
	}
    }
    $filename = File::Spec->catfile($dirname, $starttime);
    
    if (open(DATAFILE, '>' . $filename)) {
	print DATAFILE $rawreport;
	close(DATAFILE);
    }
    else {
	print "Unable to open $filename for writing, aborting.\n";
    }
}
else {
    # missing parameters, throw away the report.
}
