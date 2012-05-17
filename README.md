Baseline-Filesystem
===================

Enterprise Unix Filesystem Monitoring Solution (AIX, HP-UX, Linux, Solaris)

I wrote this script to serve as an enterprise-class file system monitor providing individual server owners the means to modify their own thresholds and escalations. As written, the script will check all local file systems as defined per OS class, as well as NFS-mounted systems, and compare their current utilization against targets stored in a configuration file. Targets can be set based on percentage utilization, or in kilobytes/megabytes/gigabytes free remaining.

This script currently assumes the existence of HP Operations Manager, because it was written with that environment in mind, but could be modified to run through cron or any other scheduling system. All notifications are currently written to a log, but this again could be modified to sending e-mail or calling any other external notification program.

This script is provided as an example of coding capability, and should not be taken as a ready-to-run project.