#!/usr/bin/perl

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
