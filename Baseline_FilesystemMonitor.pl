#!/opt/OV/contrib/perl/bin/perl -w

use strict;
use Getopt::Long;

$| = 1;
my $config = "/var/opt/OVconf/Baseline_FilesystemMonitor.conf";
my $log = "/var/opt/OV/log/Baseline_FilesystemMonitor.log";
my @tps = localtime(time());
my $tm = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $tps[5]+1900, $tps[4]+1, $tps[3], $tps[2], $tps[1], $tps[0]); my $help = 0; my $test = 0; my $verbose = 0; my $function = ""; my $filesys = ""; my $application = ""; my $package = ""; my $threshold = ""; my $response = ""; my $ignore = "";

my $result = GetOptions(
        'help' => \$help,
        'test' => \$test,
        'verbose' => \$verbose,
        'function=s' => \$function,
        'filesys=s' => \$filesys,
        'application=s' => \$application,
        'package=s' => \$package,
        'threshold=s' => \$threshold,
        'response=s' => \$response,
        'ignore' => \$ignore,
);

if ($help) {
        print "Usage: $0 [-test] [-verbose] [-help] [-function=FUNCTION] [parameters]\n";
        print "where FUNCTION is one of the following:\n";
        print "\tcheck: \n";
        print "\t\tTakes no arguments, validates the configuration file.\n";
        print "\tset -filesys=<FS> -application=<APP> [-package=<PKG>] -threshold=<TH> -response=<RESP> [-ignore]: \n";
        print "\t\tAdds or updates the entry in the configuration file for file system FS, response RESP, to match the specified values\n";
        print "\tunset -filesys=<FS> -response=<RESP>: \n";
        print "\t\tRemoves the entry in the configuration file for file system FS, response RESP.\n";
        print "\tget [-filesys=<FS>] [-application=<APP>] [-package=<PKG>] [-response=<RESP>]: \n";
        print "\t\tLists all entries in the configuration file matching the specified parameters.\n";
        print "\n";
        print "-test: Display output to screen, but generate no alarms.\n";
        print "-verbose: Display runtime conditions to screen.\n";
        print "-help: Display this message and exit.\n";
        print "\n";
        print "If $0 is called without the -function parameter, it will execute as normal.\n";
        exit();
} elsif ($function eq "check") {
        &test_config($config);
} elsif ($function eq "set") {
        my $fses = &read_config($config);
        $fses = &set_config($fses, $filesys, $application, $package, $threshold, $response, $ignore);
        &write_config($fses, $config);
} elsif ($function eq "unset") {
        my $fses = &read_config($config);
        $fses = &unset_config($fses, $filesys, $response);
        &write_config($fses, $config);
} elsif ($function eq "get") {
        my $fses = &read_config($config);
        &print_config($fses, $filesys, $application, $package, $response); } else {
        my $fses = &read_config($config);
        $fses = &read_fses($fses);
        &process_fses($fses, $tm, $log);
        &write_config($fses, $config);
}

#----- Simple, isn't it? All the magic happens below -----

sub test_config {
# Input
# 1. $file (string): Path to configuration file # # Function
#    Checks for the existence of the configuration file
#    Validates rules in the configuration file
#    Prints all issues with the configuration file
#
# Output
#    none

        my $file = shift @_;
        my $href;
        my $ignore;

        my ($app, $fs, $pkg, $thresh, $thresh_type, $resp);

        unless (-r $file) {
                print("Baseline_FilesystemMonitor.pl (Test): $file doesn't exist.\n");
                exit();
        }

        unless (open(INF, "<$file")) {
                print("Baseline_FilesystemMonitor.pl (Test): Can't open $file for reading: $!\n");
                exit();
        }

        my $count = 0;
        while (my $line = <INF>) {
                $ignore = 0;
                $count++;
                chomp($line);
                if ($line =~ /^#/) {
                        next;
                }
                if ($line =~ /^\s*$/) {
                        next;
                }
                if ($line =~ /^#?\s*([^:]+):([^:]*):([^:]*):([^:]+):([^:]+)$/) {
                        ($fs, $app, $pkg, $thresh, $resp) = ($1, $2, $3, $4, $5);
                        if (($resp ne "REMEDY") && ($resp ne "EMAIL") && ($resp ne "CALL") && ($resp ne "BRIDGE")) {
                                print("Baseline_FilesystemMonitor.pl (Test): Line $count has invalid response type; must be one of EMAIL|REMEDY|CALL|BRIDGE\n");
                        }
                        if ($thresh !~ /^\d+[%KMG]?$/) {
                                print("Baseline_FilesystemMonitor.pl (Test): Line $count has invalid threshold; must match /\\d+[%KMG]?/\n");
                        }
                } else {
                        print("Baseline_FilesystemMonitor.pl (Test): Line $count has invalid format.\n");
                }
        }
        close(INF);
}

sub set_config {
# Input
# 1. $conf (hash reference): Existing configuration # 2. $fs (string): File system name (No default) # 3. $app (string): Application name (defaults to Unix) # 4. $pkg (string): Package name (defaults to blank) # 5. $th (string): Threshold in format \d{1,2}[%KMG]? (No default) # 6. $resp (string): Response (no default) # 6. $ig (integer): Ignore (defaults to zero) # # Function
#    Checks existing configuration hashref for $conf->{"$fs"}->{"$resp"}
#    Updates all other fields if so
#
# Output
# 1. $fses (string): Path to configuration file

        my $conf = shift @_;
        my $fs = shift @_;
        my $app = shift @_;
        my $pkg = shift @_;
        my $th = shift @_;
        my $resp = shift @_;
        my $ig = shift @_;

        if ($fs eq "") {
                print "Baseline_FilesystemMonitor.pl (Set): Filesystem can't be blank!\n";
                exit();
        }
        if (($resp ne "REMEDY") && ($resp ne "EMAIL") && ($resp ne "CALL") && ($resp ne "BRIDGE")) {
                print "Baseline_FilesystemMonitor.pl (Set): Response type \"$resp\" invalid; must be one of EMAIL, REMEDY, CALL, BRIDGE\n";
        }
        if ($th !~ /^\d+[%KMG]?$/) {
                print "Baseline_FilesystemMonitor.pl (Set): Threshold \"$th\" invalid; must match regexp /\\d+[%KMG]?\$/\n";
                exit();
        }
        $conf->{"$fs"}->{"app"} = $app;
        $conf->{"$fs"}->{"pkg"} = $pkg;
        $conf->{"$fs"}->{"$resp"}->{"thresh"} = $th;
        $conf->{"$fs"}->{"$resp"}->{"ignore"} = $ignore;
        return $conf;
}

sub unset_config {
# Input
# 1. $conf (hash reference): Existing configuration # 2. $fs (string): File system name (No default) # 3. $resp (string): Response (No default) # # Function
#    Removes the check for the named file system and response
#
# Output
# 1. $fses (string): Path to configuration file

        my $conf = shift @_;
        my $fs = shift @_;
        my $resp = shift @_;

        if ($fs eq "") {
                print "Baseline_FilesystemMonitor.pl (Unset): Filesystem can't be blank!\n";
                exit();
        }
        if (not exists ($conf->{"$fs"})) {
                print "Baseline_FilesystemMonitor.pl (Unset): Filesystem $fs doesn't exist!\n";
                exit();
        }
        if (($resp ne "REMEDY") && ($resp ne "EMAIL") && ($resp ne "CALL") && ($resp ne "BRIDGE")) {
                print "Baseline_FilesystemMonitor.pl (Unset): Response type \"$resp\" invalid; must be one of EMAIL, REMEDY, CALL, BRIDGE\n";
                exit();
        }
        if (exists($conf->{"$fs"}->{"$resp"})) {
                delete $conf->{"$fs"}->{"$resp"};
        } else {
                print "Baseline_FilesystemMonitor.pl (Unset): Filesystem $fs has no threshold for action $resp!\n";
                exit();
        }
        return $conf;
}

sub print_config {
# Input
# 1. $conf (hash reference): Existing configuration # 2. $fs (string): File system name (No default) # 3. $app (string): Application (No default) # 3. $pkg (string): Response (Defaults to blank) # 3. $resp (string): Response (No default) # # Function
#    Removes the check for the named file system and response
#
# Output
# none

        my $conf = shift @_;
        my $fs = shift @_;
        my $app = shift @_;
        my $pkg = shift @_;
        my $resp = shift @_;
        my $ignored;
        my $line;

        for my $key (sort keys %$conf) {
                if (($fs eq "") || ($key eq $fs)) {
                        for my $rsp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                if (exists($conf->{"$key"}->{"$rsp"}->{"ignore"}) && ($conf->{"$key"}->{"$rsp"}->{"ignore"} == 1)) {
                                        $ignored = "[IGNORED] ";
                                } else {
                                        $ignored = "";
                                }
                                if ((($resp eq "") || ($resp eq $rsp)) && exists($conf->{"$key"}->{"$rsp"}->{"thresh"})) {
                                        if ((($app eq "") || ($app eq $conf->{"$fs"}->{"app"})) &&
                                                        (($pkg eq "") || ($pkg eq $conf->{"$fs"}->{"pkg"}))) {
                                                $line = sprintf("%s%s (App '%s'/Pkg '%s'): %s at threshold %s",
                                                        $ignored,
                                                        $key,
                                                        $conf->{"$key"}->{"app"},
                                                        $conf->{"$key"}->{"pkg"},
                                                        $rsp,
                                                        $conf->{"$key"}->{"$rsp"}->{"thresh"},
                                                );
                                                print "$line\n";
                                        }
                                }
                        }
                }
        }
}

sub fail {
# Input
# 1. TIME (string): timestamp of execution.
# 1. ERROR (string): Message text.
# 2. SEV (string): Severity of alarm
# 3. LOG (string): Log to which to write # # Function
#    Writes a log entry indicating failure in execution. Does not exit.
#
# Output
#    none

        my $time = shift @_;
        my $error = shift @_;
        my $sev = shift @_;
        my $out = shift @_;

        my $msg = sprintf("[%s] OM - Unix: %s [%s]",
                $time,
                $error,
                $sev,
        );
        open(ERR, ">>$out");
        print ERR "$msg\n";
        close(ERR);
}

sub make_config {
# Input
# 1. $fullpath (string): Full path to new configuration file # # Function
#    Reads old dskspc.conf file
#    Creates new Baseline_FilesysMonitor.conf based on past values
#
# Output
#    none

        my $fullpath = shift @_;
        my @pts = split(/\//, $fullpath);
        my $file = pop(@pts);
        my $path = join("/", @pts) . "/";
        my @old_parts;
        my $appl;
        my $pkg;
        my $dis;

        unless (-d $path) {
                system("mkdir -p $path");
        }

        my $old_file = "/var/opt/OV/conf/OpC/custom/filesys_monitor/dskspc.conf";
        open(IN, "<$old_file");
        my @old_entries = ();
        my $string = "";
        while (my $line = <IN>) {
                $appl = "";
                $dis = "";
                $pkg = "";
                chomp($line);
                if ($line =~ /^#/) {
                        next;
                }
                if ($line =~ /^\s*$/) {
                        next;
                }
                @old_parts = split(/:/, $line);
                if (scalar(@old_parts) > 4) {
                        $appl = $old_parts[4];
                }
                if (scalar(@old_parts) > 5) {
                        $dis = $old_parts[5];
                }
                if ($dis eq "Transient") {
                        $pkg = "";
                }
                $appl = &map_team_to_appl($appl);
                $string = sprintf("%s:%s:%s:%d%%:REMEDY",
                        $old_parts[0],
                        $appl,
                        $pkg,
                        $old_parts[1],
                );
                if ($dis eq "Disabled") {
                        $string = "# " . $string;
                }
                push (@old_entries, $string);
                $string = sprintf("%s:%s:%s:%d%%:CALL",
                        $old_parts[0],
                        $appl,
                        $pkg,
                        $old_parts[2],
                );
                if ($dis eq "Disabled") {
                        $string = "# " . $string;
                }
                push (@old_entries, $string);
                if ($verbose) {
                        print "$line ==> $string\n";
                }
        }

        if (not $test) {
                unless (open(OUT, ">$fullpath")) {
                        fail($tm, "Can't open $fullpath for writing!", "minor", $log);
                        exit();
                }
                print OUT "# OpenView File System Monitoring\n";
                print OUT "# The OpenView file system monitor (Baseline_FilesystemMonitor_log) uses the\n";
                print OUT "# following file format:\n";
                print OUT "\n";
                print OUT "# <Filesystem>:[Application]:[Package]:<Threshold>:<RESPONSE>\n";
                print OUT "\n";
                print OUT "# For documentation, please see the following:\n";
                print OUT "# http://eit.ido.infonet.t-mobile.com/Monitoring_and_Tools/monitored_apps/Monitored%20Applications/Baseline/OpenView%20File%20System%20Monitoring.docx\n";
                print OUT "\n";
                foreach $string (@old_entries) {
                        print OUT "$string\n";
                }
                close(OUT);
        }
}

sub map_team_to_appl {
# Input
# 1. $team_name (string): Old dskspc.conf code indicating team name # # Function
#    Generates a "best-guess" application name based on old dskspc.conf code
#
# Output
#    $appl_name: New EAL-consistent application name

        my $team_name = shift @_;
        my $appl_name = "";

        # Fix this
        ($team_name eq "AS_BO") && ($appl_name = "Remedy - IT");
        ($team_name eq "AS_CC_Web_Tools") && ($appl_name = "Doczine");
        ($team_name eq "AS_Mid_Int") && ($appl_name = "Tuxedo - Watson/RSP");
        ($team_name eq "AS_Int") && ($appl_name = "Tibco - HSO");
        ($team_name eq "AS_Mid") && ($appl_name = "Tuxedo - Watson/RSP");
        ($team_name eq "AS_PP") && ($appl_name = "Jpay");
        ($team_name eq "AS_Rep_DW") && ($appl_name = "Data Warehouse");
        ($team_name eq "AS_Rep_OR") && ($appl_name = "");
        ($team_name eq "AS_Data_WH") && ($appl_name = "EDW");
        ($team_name eq "AS_Sales_Ops") && ($appl_name = "");
        ($team_name eq "AS_Self_Care") && ($appl_name = "");
        ($team_name eq "AS_Web_Services") && ($appl_name = "T-Mobile.com");
        ($team_name eq "AS_Supply") && ($appl_name = "PKMS");
        ($team_name eq "Amdocs") && ($appl_name = "Samson Core - Customer Billing");
        ($team_name eq "Amdocs AS CSM") && ($appl_name = "CSM");
        ($team_name eq "Amdocs_Dev") && ($appl_name = "Samson - Pet");
        ($team_name eq "Amdocs_BEM") && ($appl_name = "Samson Admin and Reporting - Archive Engine");
        ($team_name eq "Amdocs_IOPENV") && ($appl_name = "Samson - Pet");
        ($team_name eq "Amdocs_Inf_Prd") && ($appl_name = "Samson Middleware - API Link");
        ($team_name eq "EUSA-SAMSON") && ($appl_name = "Samson Middleware - API Link");
        ($team_name eq "BOM_East") && ($appl_name = "HR Docs");
        ($team_name eq "BOM_West") && ($appl_name = "Remedy - IT");
        ($team_name eq "BI") && ($appl_name = "BIF");
        ($team_name eq "BI_Dev") && ($appl_name = "BIF");
        ($team_name eq "Bill_Ops") && ($appl_name = "Samson Core - Customer Billing");
        ($team_name eq "BPS-Billing") && ($appl_name = "Samson Core - Customer Billing");
        ($team_name eq "Centivia") && ($appl_name = "Centivia");
        ($team_name eq "CCT") && ($appl_name = "CCT");
        ($team_name eq "CMS") && ($appl_name = "CCM");
        ($team_name eq "CSM-EUSA") && ($appl_name = "Samson Middleware - Tuxedo - Watson/RSP");
        ($team_name eq "Comptel") && ($appl_name = "Comptel");
        ($team_name eq "Datacom") && ($appl_name = "");
        ($team_name eq "DBA") && ($appl_name = "Oracle");
        ($team_name eq "DBA-SAMSON") && ($appl_name = "Samson Core - Customer Database");
        ($team_name eq "DBA_archive") && ($appl_name = "Oracle");
        ($team_name eq "DevESG") && ($appl_name = "Tibco - HSO");
        ($team_name eq "EBSS") && ($appl_name = "TES");
        ($team_name eq "EBSS-Back") && ($appl_name = "TES");
        ($team_name eq "EBSS-DBA") && ($appl_name = "Oracle");
        ($team_name eq "EBSS-Sched") && ($appl_name = "TES");
        ($team_name eq "ECPS") && ($appl_name = "EMC Control Center");
        ($team_name eq "ENM") && ($appl_name = "");
        ($team_name eq "EMG") && ($appl_name = "OM - Unix");
        ($team_name eq "EODA-NS") && ($appl_name = "Oracle");
        ($team_name eq "ERS") && ($appl_name = "ERS");
        ($team_name eq "ES_DBA_Tst_Trn") && ($appl_name = "Oracle");
        ($team_name eq "ES_DBA_App_Svcs") && ($appl_name = "Oracle");
        ($team_name eq "ES_DBA_Bill") && ($appl_name = "Samson Core - Customer Database");
        ($team_name eq "ES_DBA_NPB") && ($appl_name = "Samson Core - Customer Database");
        ($team_name eq "ES_SEC") && ($appl_name = "Unix");
        ($team_name eq "ES_UNIX_G1") && ($appl_name = "Unix");
        ($team_name eq "ES_UNIX_G2") && ($appl_name = "Unix");
        ($team_name eq "ES_UNIX_G3") && ($appl_name = "Unix");
        ($team_name eq "ES_UNIX_Security") && ($appl_name = "Unix");
        ($team_name eq "ESDS") && ($appl_name = "Active Directory");
        ($team_name eq "ESG") && ($appl_name = "Tibco - HSO");
        ($team_name eq "ESP") && ($appl_name = "");
        ($team_name eq "ETCM") && ($appl_name = "");
        ($team_name eq "ETDS") && ($appl_name = "Active Directory");
        ($team_name eq "ETMW") && ($appl_name = "Tibco - HSO");
        ($team_name eq "EUSA") && ($appl_name = "Unix");
        ($team_name eq "Infinys") && ($appl_name = "IRB");
        ($team_name eq "IT_AR_OPS") && ($appl_name = "");
        ($team_name eq "ITCO") && ($appl_name = "");
        ($team_name eq "Kintana") && ($appl_name = "");
        ($team_name eq "Narus") && ($appl_name = "");
        ($team_name eq "NetSec") && ($appl_name = "");
        ($team_name eq "OPS_AR") && ($appl_name = "");
        ($team_name eq "OSBL") && ($appl_name = "Unix");
        ($team_name eq "PAG") && ($appl_name = "PAG");
        ($team_name eq "Prov") && ($appl_name = "DSPA - Provisioning");
        ($team_name eq "QAD") && ($appl_name = "");
        ($team_name eq "RevVis") && ($appl_name = "");
        ($team_name eq "ROAMING") && ($appl_name = "");
        ($team_name eq "SAP") && ($appl_name = "SAP - ECC");
        ($team_name eq "SC") && ($appl_name = "");
        ($team_name eq "Siebel_AS") && ($appl_name = "");
        ($team_name eq "SSO_RFM") && ($appl_name = "WATSON - Admin");
        ($team_name eq "Subex") && ($appl_name = "");
        ($team_name eq "Suncom") && ($appl_name = "");
        ($team_name eq "TMO Premier") && ($appl_name = "T-Mobile Premier");
        ($team_name eq "Tiger") && ($appl_name = "");
        ($team_name eq "Usage") && ($appl_name = "eBill");

        if ($appl_name eq "") {
                $appl_name = "Unix";
        }
        return $appl_name;
}

sub read_config {
# Input
# 1. $file (string): Path to configuration file # # Function
#    Checks for the existence of the configuration file
#    Creates the configuration file if it doesn't exist
#    Reads file system thresholds and alarm information from the configuration file into an internal data structure
#
# Output
#    $href (scalar): Reference to internal data structure for storing file system information

        my $file = shift @_;
        my $href;
        my $ignore;

        my ($app, $fs, $pkg, $thresh, $thresh_type, $resp);

        unless (-r $file) {
                fail($tm, "$file doesn't exist; creating.", "warning", $log);
                &make_config($file);
        }

        unless (open(INF, "<$file")) {
                fail($tm, "Can't open $file for reading: $!", "minor", $log);
                exit();
        }

        my $count = 0;
        while (my $line = <INF>) {
                $ignore = 0;
                $count++;
                chomp($line);
                if ($line =~ /^#/) {
                        $ignore = 1;
                }
                if ($line =~ /^\s*$/) {
                        next;
                }
                if ($line =~ /^#?\s*([^:]+):([^:]*):([^:]*):([\d]+[%KMG]?):([^:]+)$/) {
                        ($fs, $app, $pkg, $thresh, $resp) = ($1, $2, $3, $4, $5);
                        $href->{"$fs"}->{"app"} = $app;
                        $href->{"$fs"}->{"pkg"} = $pkg;
                        if (($resp ne "REMEDY") && ($resp ne "EMAIL") && ($resp ne "CALL") && ($resp ne "BRIDGE")) {
                                fail($tm, "Line $count of file system monitor conf has invalid response type; setting to CALL", "warning", $log);
                                $resp = "CALL";
                        }
                        if ($thresh eq "") {
                                $thresh = "95%";
                        }
                        if ($thresh =~ /^\d+$/) {
                                $thresh .= "%";
                        }
                        $href->{"$fs"}->{"$resp"}->{"thresh"} = $thresh;
                        $href->{"$fs"}->{"total"} = 0;
                        $href->{"$fs"}->{"avail"} = 0;
                        $href->{"$fs"}->{"$resp"}->{"ignore"} = $ignore;
                        $href->{"$fs"}->{"$resp"}->{"check"} = (1 - $ignore);
                } else {
                        unless ($ignore) {
                                fail($tm, "Line $count of file system monitor conf has invalid format; ignoring", "warning", $log);
                        }
                }
        }
        close(INF);
        return $href;
}

sub read_fses {
# Input
# 1. $href (scalar): Reference to internal data structure for storing file system information # # Function
#    Identifies the necessary functions to parse the file system structure
#    Parses the file system structure present on the system and updates the internal data structure with current file system statistics
#
# Output
#    $href (scalar): Reference to internal data structure for storing file system information udpated with current file system information

        my $href = shift @_;
        my $OS = `uname`;
        chomp($OS);
        my $read_one_df = "";
        my $get_fs_list = "";
        my $fs_types = "";
        my @fses = ();
        my $thresh;
        my $thresh_type;


        if ($OS =~ /HP-UX/) {
                $read_one_df = "/usr/bin/bdf";
                $get_fs_list = \&get_HPUX_list;
                $fs_types = qr/hfs|vxfs|nfs/;
        } elsif ($OS =~ /SunOS/) {
                $read_one_df = "df -k";
                $get_fs_list = \&get_SunOS_list;
                $fs_types = qr/ufs|vxfs|zfs|nfs/;
        } elsif ($OS =~ /AIX/) {
                $read_one_df = "df -I -k";
                $get_fs_list = \&get_AIX_list;
                $fs_types = qr/jfs|vxfs|nfs/;
        } elsif ($OS =~ /Linux/) {
                $read_one_df = "/bin/df -k";
                $get_fs_list = \&get_Linux_list;
                $fs_types = qr/ext|vxfs|nfs/;
        } else {
                &fail($tm, "Can't identify OS type from uname: $OS", "minor", $log);
                exit();
        }

        @fses = &get_fses($get_fs_list, $fs_types);
        foreach my $pair (@fses) {
                print "Returned: $pair\n";
                my ($fs, $type) = split(/%/, $pair);
                if (not exists($href->{"$fs"})) {
                        $href->{"$fs"}->{"app"} = "Unix";
                        $href->{"$fs"}->{"pkg"} = "";
                        if (lc($type) =~ /nfs/) {
                                $href->{"$fs"}->{"CALL"}->{"thresh"} = "99%";
                        } else {
                                $href->{"$fs"}->{"CALL"}->{"thresh"} = "95%";
                        }
                        $href->{"$fs"}->{"CALL"}->{"ignore"} = 0;
                        $href->{"$fs"}->{"CALL"}->{"check"} = 1;
                        if (lc($type) =~ /nfs/) {
                                $href->{"$fs"}->{"REMEDY"}->{"thresh"} = "98%";
                        } else {
                                $href->{"$fs"}->{"REMEDY"}->{"thresh"} = "90%";
                        }
                        $href->{"$fs"}->{"REMEDY"}->{"ignore"} = 0;
                        $href->{"$fs"}->{"REMEDY"}->{"check"} = 1;
                        $href->{"$fs"}->{"total"} = 0;
                        $href->{"$fs"}->{"avail"} = 0;
                }
        }
        foreach my $fs (keys %$href) {
                if (not $href->{"$fs"}->{"ignore"}) {
                        $href = &read_fs($href, $read_one_df, $fs);
                }
        }
        return $href;
}

sub get_fses {
# Input
# 1. $read_cmd (scalar): Reference to subroutine for a specific OS # 2. $fs_types (string): Pre-compiled regexp of file system types that are appropriate for the specific OS # # Function
#    Spawns a child process to read the currently-mounted file systems.
#    Watches for data on currently-mounted file systems from the child process
#    Terminates the child process with an error if no data are turned in 60 seconds.
#
# Output
#    @fses (array): List of file systems presently on the server that need to be parsed for thresholds

        my $read_cmd = shift @_;
        my $fs_types = shift @_;

        my $timer = 0;
        my $size;
        my $wait;
        my $from_child;
        my $fs;
        my @fses = ();
        my $success = 0;
        my @fs_list = ();

        if (my $pid = open(FROM, "-|")) {
                $timer = 0;
                $wait = waitpid($pid, 0);
                $from_child = "";
                while (($wait > 0) && ($timer < 60)) {
                        sleep 5;
                        $timer+=5;
                        $size .= read(FROM, $from_child, 1024*1024);
                        while ($from_child =~ /~([^~]+)~/) {
                                $fs = $1;
                                push(@fses, $fs);
                                $from_child =~ s/~$1//;
                                $success = 1;
                        }
                        $wait = waitpid($pid, 0);
                }
                if ($timer >= 30) {
                        fail($tm, "Generating file system listing > 60sec", "major", $log);
                        kill(9, $pid);
                }
                if ($success == 0) {
                        fail($tm, "Could not generate file system listing; insufficient data returned", "major", $log);
                }
                close FROM;
        } else {
                $from_child = "~";
                @fs_list = &$read_cmd($fs_types);
                while ($fs = shift(@fs_list)) {
                        $from_child .= $fs . "~";
                }
                print $from_child;
                exit();
        }
        return @fses;
}

sub read_fs {
# Input
# 1. $href (scalar): Reference to internal data structure of file system information # 2. $df (scalar): Reference to shell command for returning file system information # 3. $fs (string): File system to be analyzed # # Function
#    Spawns a child process to read the named file system's current total and available space
#    Watches for data to be returned from the child process
#    Terminates the child process with an error if no data are turned in 30 seconds.
#
# Output
# 1. $href (scalar): Reference to internal data structure of file system information containing named file system information

        my $href = shift @_;
        my $df = shift @_;
        my $fs = shift @_;

        my $timer;
        my $wait;
        my $from_child;
        my @split;
        my $df_info;
        my $size;
        my $success;

        my $pkg = $href->{"$fs"}->{"pkg"};
        if ($pkg ne "") {
                my $clus = `which ovclusterinfo 2>&1`;
                chomp($clus);
                if ($clus =~ /no ovclusterinfo in/) {
                        foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                if(exists($href->{"$fs"}->{"$resp"}->{"check"})) {
                                        $href->{"$fs"}->{"$resp"}->{"check"} = 0;
                                }
                        }
                } else {
                        my $active = `$clus -g $pkg -ls 2>&1`;
                        $active =~ s/\s//g;
                        if ($active ne "Online") {
                                foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                        if(exists($href->{"$fs"}->{"$resp"}->{"check"})) {
                                                $href->{"$fs"}->{"$resp"}->{"check"} = 0;
                                        }
                                }
                        }
                }
        }
        my $check = 0;
        foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                if((exists($href->{"$fs"}->{"$resp"}->{"check"})) && ($href->{"$fs"}->{"$resp"}->{"check"} == 1)) {
                        $check = 1;
                }
        }
        if (not $check) {
                return $href;
        }

        if (my $pid = open(FROM, "-|")) {
                $timer = 0;
                $wait = waitpid($pid, 0);
                $from_child = "";
                $success = 0;
                while (($wait > 0) && ($timer < 30)) {
                        sleep 5;
                        $timer+=5;
                        $size .= read(FROM, $from_child, 1024*1024);
                        if ($from_child =~ /~Mount: (.+)~/) {
                                $href->{"$fs"}->{"mount"} = $1;
                        }
                        if ($from_child =~ /~Avail: (\d+)~/) {
                                $href->{"$fs"}->{"avail"} = $1;
                        }
                        if ($from_child =~ /~Total: (\d+)~/) {
                                $href->{"$fs"}->{"total"} = $1;
                        }
                        if (($href->{"$fs"}->{"avail"} > 0) && ($href->{"$fs"}->{"total"} > 0)) {
                                $success = 1;
                        }
                        $wait = waitpid($pid, 0);
                }
                if ($timer >= 30) {
                        fail($tm, "File system $fs may be broken; response time > 30sec", "major", $log);
                        kill(9, $pid);
                        foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                if(exists($href->{"$fs"}->{"$resp"}->{"check"})) {
                                        $href->{"$fs"}->{"$resp"}->{"check"} = 0;
                                }
                        }
                }
                if ($success == 0) {
                        fail($tm, "File system $fs may be missing; insufficient data returned", "minor", $log);
                        foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                if(exists($href->{"$fs"}->{"$resp"}->{"check"})) {
                                        $href->{"$fs"}->{"$resp"}->{"check"} = 0;
                                }
                        }
                }
                close FROM;
        } else {
                $from_child = "~";
                unless (open(DF, "$df $fs |")) {
                        &fail($tm, "Can't run '$df': $!", "minor", $log);
                        exit();
                }
                my $line = <DF>; # Header
                while ($line = <DF>) {
                        chomp($line);
                        $df_info .= $line;
                }
                if ((defined $df_info) && ($df_info !~ /Cannot find/)) {
                        @split = split(/\s+/, $df_info);
                        my $mount = $split[0];
                        if ($mount !~ /:/) {
                                $mount = $fs;
                        }
                        $from_child = "~Avail: " . $split[3] . "~Total: " . $split[1] . "~Mount: " . $mount . "~";
                }
                print $from_child;
                close DF;
                exit();
        }
        return $href;
}

sub process_fses {
# Input
# 1. $href (scalar): Reference to internal data structure of file system information # 2. $time (string): Time at the start of execution of the script for logging purposes # 3. $out (string): Name of the logfile to which the script will write # # Function
#    Opens the logfile for writing
#    Checks all file systems against their defined thresholds
#    Writes all alarms to the logfile
#    Closes the logfile for writing
#
# Output
#    none

        my $href = shift @_;
        my $time = shift @_;
        my $out = shift @_;
        my $clus;
        my $cont;
        my $nfs;

        unless (open(OUTF, ">>$out")) {
                fail($tm, "Can't open $out for appending: $!", "minor", $log);
                exit();
        }

        foreach my $key (keys %$href) {
                $cont = 1;
                foreach my $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                        if ($verbose) {
                                print "FS: $key\tRESP: $resp... ";
                        }
                        if (($cont) && ($href->{"$key"}->{"$resp"}->{"check"})) {
                                if (exists($href->{"$key"}->{"$resp"}->{"thresh"})) {
                                        if ($verbose) {
                                                print "$key / $resp : " . $href->{"$key"}->{"$resp"}->{"thresh"} . " / " . $href->{"$key"}->{"total"} . " / " . $href->{"$key"}->{"avail"} . "\n";
                                        }
                                        $href->{"$key"}->{"value"} = &over_thresh($href->{"$key"}->{"$resp"}->{"thresh"},
                                                $href->{"$key"}->{"total"}, $href->{"$key"}->{"avail"});
                                        if ($href->{"$key"}->{"value"} ne "_") {
                                                my $cond_word = "below";
                                                my $cond_symb = "<";
                                                if ($href->{"$key"}->{"value"} =~ /%/) {
                                                        $cond_word = "above";
                                                        $cond_symb = ">";
                                                }
                                                if ($href->{"$key"}->{"mount"} ne $key) {
                                                        $nfs = "NFS ";
                                                } else {
                                                        $nfs = "";
                                                }
                                                my $outstr = sprintf(
                                                        "[%s] %s: %sFilesystem \"%s\" %s threshold (%s %s %s) [%s]",
                                                        $tm,
                                                        $href->{"$key"}->{"app"},
                                                        $nfs,
                                                        $href->{"$key"}->{"mount"},
                                                        $cond_word,
                                                        $href->{"$key"}->{"value"},
                                                        $cond_symb,
                                                        $href->{"$key"}->{"$resp"}->{"thresh"},
                                                        $resp,
                                                );
                                                if (not $test) {
                                                        print OUTF "$outstr\n";
                                                }
                                                if (($verbose) || ($test)) {
                                                        print "$outstr\n";
                                                }
                                                $cont = 0;
                                        } else {
                                                if ($verbose) {
                                                        print "no alarm\n";
                                                }
                                        }
                                }
                        } else {
                                if ($verbose) {
                                        print "already alarmed or not in file\n";
                                }
                        }
                }
        }
        close(OUTF);
}

sub over_thresh {
# Input
# 1. $thresh (string): Threshold for alarming # 2. $total (integer): Total space in the file system # 3. $avail (integer): Available space remaining in the file system # # Function
#    Identifies type of threshold against which to test
#    Tests threshold using total and available space on the file system
#    Returns overage if threshold is exceeded, otherwise returns ""
#
# Output
#    $over (string): Overage if threshold is exceeded, empty string otherwise.

        my $thresh = shift @_;
        my $total = shift @_;
        my $avail = shift @_;
        my $over = "_";

        $thresh =~ /^(\d+)([%KMG]?)$/;
        my ($t_val, $t_type) = ($1, $2);
        if ($t_type eq "") {
                $t_type = "%";
        }

        if ($t_type eq "%") {
                if ($t_val < (int(($total - $avail) * 100 / $total))) {
                        $over = int(($total - $avail) * 100 / $total) . "%";
                }
        } elsif ($t_type eq "K") {
                if ($t_val > $avail) {
                        $over = $avail . "K";
                }
        } elsif ($t_type eq "M") {
                if ($t_val > (int($avail/1024))) {
                        $over = int($avail/1024) . "M";
                }
        } elsif ($t_type eq "G") {
                if ($t_val > (int($avail/(1024*1024)))) {
                        $over = int($avail/(1024*1024)) . "G";
                }
        } else {
                fail($tm, "Invalid threshold type: ${t_type}", "minor", $log);
                return "_";
        }
        return $over;
}

sub write_config {
# Input
# 1. $href (scalar): Reference to internal data structure containing file system information # 2. $fullpath (string): Location of configuration file on the system # # Function
#    Opens configuration file for writing
#    Writes out file system configuration information to disk
#    Closes configuration file
#
# Output
#    none

        my $href = shift @_;
        my $fullpath = shift @_;
        my $key;
        my $resp;
        my $string;

        my @pts = split(/\//, $fullpath);
        my $file = pop(@pts);
        my $path = join("/", @pts) . "/";
        unless (-d $path) {
                system("mkdir -p $path");
        }

        if (not $test) {
                unless (open(OUT, ">$fullpath")) {
                        fail($tm, "Can't open $fullpath for writing!", "minor", $log);
                        exit();
                }
                print OUT "# OpenView File System Monitoring\n";
                print OUT "# The OpenView file system monitor (Baseline_FilesystemMonitor_log) uses the\n";
                print OUT "# following file format:\n";
                print OUT "\n";
                print OUT "# <Filesystem>:[Application]:[Package]:<Threshold>:<RESPONSE>\n";
                print OUT "\n";
                print OUT "# For documentation, please see the following:\n";
                print OUT "# http://eit.ido.infonet.t-mobile.com/Monitoring_and_Tools/monitored_apps/Monitored%20Applications/Baseline/OpenView%20File%20System%20Monitoring.docx\n";
                print OUT "\n";
                foreach $key (sort keys %$href) {
                        foreach $resp ("BRIDGE", "CALL", "REMEDY", "EMAIL") {
                                if ((exists($href->{"$key"}->{"$resp"}->{"thresh"}))) {
                                        my $ign_this = 0;
                                        if ($href->{"$key"}->{"pkg"} eq "Transient") {
                                                $href->{"$key"}->{"pkg"} = "";
                                        }
                                        $string = sprintf("%s:%s:%s:%s:%s",
                                                $key,
                                                $href->{"$key"}->{"app"},
                                                $href->{"$key"}->{"pkg"},
                                                $href->{"$key"}->{"$resp"}->{"thresh"},
                                                $resp,
                                        );
                                        if ($href->{"$key"}->{"$resp"}->{"ignore"}) {
                                                $ign_this = 1;
                                        }
                                        if ($key eq "/tmp/mksysb") {
                                                $ign_this = 1;
                                        }
                                        if ($key eq "/tmp/UPM") {
                                                $ign_this = 1;
                                        }
                                        if ($key eq "/tmp/VAS") {
                                                $ign_this = 1;
                                        }
                                        if ($key eq "/vol") {
                                                $ign_this = 1;
                                        }
                                        if ($key eq "/TEMP") {
                                                $ign_this = 1;
                                        }
                                        if ($key =~ m#^/proc.*#) {
                                                $ign_this = 1;
                                        }
                                        if ($ign_this) {
                                                $string = "# " . $string;
                                        }
                                        print OUT "$string\n";
                                }
                        }
                }
                close(OUT);
                system("chown opc_op:users $fullpath");
                system("chmod 666 $fullpath");
        }
}

sub get_HPUX_list {
# Input
# 1. $fs_types (scalar): Precompiled regexp of HPUX file systems to test # # Function
#    Executes command to get list of all current filesystems
#    Identifies appropriate file systems to test
#    Returns list of file systems currently present
#
# Output
#    @fses (array): list of currently present file systems to test

        my $fs_types = shift @_;
        my $ret;
        my $fs;
        my $type;
        my @fses;

        my $cmd = "/usr/bin/df -g";
        open(FS, "$cmd |");
        while (my $line = <FS>) {
                if ($line =~ /^([^ ]+)\s*\(/) {
                        $fs = $1;
                        chomp($fs);
                }
                if ($line =~ /([^ ]+) file system type/) {
                        $type = $1;
                        chomp($type);
                        if ($type =~ $fs_types) {
                                $ret = sprintf("%s%%%s", $fs, $type);
                                push(@fses, $ret);
                        }
                }
        }
        close(FS);
        return @fses;
}

sub get_SunOS_list {
# Input
# 1. $fs_types (scalar): Precompiled regexp of Solaris file systems to test # # Function
#    Executes command to get list of all current filesystems
#    Identifies appropriate file systems to test
#    Returns list of file systems currently present
#
# Output
#    @fses (array): list of currently present file systems to test

        my $fs_types = shift @_;
        my $ret;
        my $fs;
        my $type;
        my @fses;

        my $cmd = "/usr/bin/df -ga";
        open(FS, "$cmd |");
        while (my $line = <FS>) {
                if ($line =~ /^([^ ]+)\s*\(/) {
                        $fs = $1;
                }
                if ($line =~ /([^ ]+) fstype/) {
                        $type = $1;
                        if ($type =~ $fs_types) {
                                $ret = sprintf("%s%%%s", $fs, $type);
                                push(@fses, $ret);
                        }
                }
        }
        close(FS);
        return @fses;
}

sub get_AIX_list {
# Input
# 1. $fs_types (scalar): Precompiled regexp of AIX file systems to test # # Function
#    Executes command to get list of all current filesystems
#    Identifies appropriate file systems to test
#    Returns list of file systems currently present
#
# Output
#    @fses (array): list of currently present file systems to test

        my $fs_types = shift @_;
        my $ret;
        my $fs;
        my $type;
        my @fses;

        my $cmd = "/usr/sysv/bin/df -n";
        open(FS, "$cmd |");
        while (my $line = <FS>) {
                if ($line =~ /^([^ ]+)\s*:\s*([^ ]+)/) {
                        ($fs, $type) = ($1, $2);
                        if ($type =~ $fs_types) {
                                $ret = sprintf("%s%%%s", $fs, $type);
                                push(@fses, $ret);
                        }
                }
        }
        close(FS);
        return @fses;
}

sub get_Linux_list {
# Input
# 1. $fs_types (scalar): Precompiled regexp of Linux file systems to test # # Function
#    Executes command to get list of all current filesystems
#    Identifies appropriate file systems to test
#    Returns list of file systems currently present
#
# Output
#    @fses (array): list of currently present file systems to test

        my $fs_types = shift @_;
        my $ret;
        my @fses;
        my @split;

        my $cmd = "/bin/df -Ta";
        open(FS, "$cmd |");
        while (my $line = <FS>) {
                chomp($line);
                @split = split(/\s+/, $line);
                if (scalar(@split) < 7) {
                        $line .= <FS>;
                        @split = split(/\s+/, $line);
                }
                if ($split[1] =~ $fs_types) {
                        $ret = sprintf("%s%%%s", $split[6], $split[1]);
                        push(@fses, $ret);
                }
        }
        close(FS);
        return @fses;
}
