pinglogger
==========

Logging ping times to hosts and summarizing results to an HTML file

OVERVIEW

ping_test.pl runs on a periodic basis from as many hosts as you want to 
capture details. ping_test.pl then connects to a logging host that you 
specify in the configuration file, and on the logging host, ping_test.pl
runs ping_logger.pl to store the results.

On the logging host, periodically run ping_report.pl to update the HTML 
output files with the status.


DOCUMENTATION

Each .pl contains both the script and documentation. To read the documentation, 
view with a POD viewer, for example: 

perldoc ping_test.pl

