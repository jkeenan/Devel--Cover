package Devel::Cover::cpancover;
use strict;
use warnings;
#use Data::Dumper ();  # no import of Dumper (use Devel::Cover::Dumper if needed)
use Data::Dumper;$Data::Dumper::Indent=1;
use Fcntl ":flock";
use base qw( Exporter );
our @EXPORT_OK = qw(
    new
    read_results
    write_stylesheet
    write_csv
    write_html
    get_cover
    run_cover
);
use Parallel::Iterator "iterate_as_array";

sub new {
    my ($Options) = @_;

    # Processing of command-line options has been completed;
    # processing of files listed on command-line remains.

    my $config;
    while (my ($k,$v) = each(%{$Options})) {
        $config->{$k} = $v;
    }

    $config->{outputdir}  ||= $config->{directory};
    $config->{outputfile} ||= "coverage.html";
    push @{$config->{module}}, @ARGV;
    if (!$config->{redo_cpancover_html} && !@{$config->{module}}) {
        my $d = $config->{directory};
        opendir my $D, $d or die "Can't opendir $d: $!\n";
        @{$config->{module}} = grep !/^\./ && -e "$d/$_/Makefile.PL",
                                     sort readdir $D
            or die "No module directories found\n";
        closedir $D or die "Can't closedir $d: $!\n";
    }

    return $config;
}

sub read_results {
    my $Options = shift;
    my $f = "$Options->{outputdir}/cover.results";
    my %results;

    open my $fh, "<", $f or return;
    my $try;
    until (flock $fh, LOCK_SH) {
        die "Can't lock $f: $!\n" if $try++ > 60;
        sleep 1;
    }
    while (<$fh>) {
        my ($mod, $status) = split;
        $results{$mod} = $status;
    }
    close $fh or die "Can't close $f: $!\n";

    return \%results;
}

sub default_css {
    my $css = <<EOF;
/* Stylesheet for Devel::Cover cpancover reports */

/* You may modify this file to alter the appearance of your coverage
 * reports. If you do, you should probably flag it read-only to prevent
 * future runs from overwriting it.
 */

/* Note: default values use the color-safe web palette. */

body {
    font-family: sans-serif;
}

h1 {
    text-align : center;
    background-color: #cc99ff;
    border: solid 1px #999999;
    padding: 0.2em;
    -moz-border-radius: 10px;
}

a {
    color: #000000;
}
a:visited {
    color: #333333;
}

table {
    border-spacing: 0px;
}
tr {
    text-align : center;
    vertical-align: top;
}
th,.h,.hh {
    background-color: #cccccc;
    border: solid 1px #333333;
    padding: 0em 0.2em;
    width: 2.5em;
    -moz-border-radius: 4px;
}
.hh {
    width: 25%;
}
td {
    border: solid 1px #cccccc;
    border-top: none;
    border-left: none;
    -moz-border-radius: 4px;
}
.hblank {
    height: 0.5em;
}
.dblank {
    border: none;
}

/* source code */
pre,.s {
    text-align: left;
    font-family: monospace;
    white-space: pre;
    padding: 0.2em 0.5em 0em 0.5em;
}

/* Classes for color-coding coverage information:
 *   c0  : path not covered or coverage < 75%
 *   c1  : coverage >= 75%
 *   c2  : coverage >= 90%
 *   c3  : path covered or coverage = 100%
 */
.c0 {
    background-color: #ff9999;
    border: solid 1px #cc0000;
}
.c1 {
    background-color: #ffcc99;
    border: solid 1px #ff9933;
}
.c2 {
    background-color: #ffff99;
    border: solid 1px #cccc66;
}
.c3 {
    background-color: #99ff99;
    border: solid 1px #009900;
}
EOF
    return $css;
}

sub write_stylesheet {
    my $Options = shift;
    my $css = "$Options->{outputdir}/cpancover.css";
    open my $CSS, ">", $css or return;
    print $CSS default_css();
    close $CSS or die "Can't close $css: $!\n";
}

sub write_csv {
	my ($data,$Options) = @_;

	open(my $fh, ">", "$Options->{outputdir}/cpan_cover.csv")
		or die "cannot open > cpan_cover.txt: $!";
	# release, distribution,link,
	#	branch_class,branch_details,branch_pc,
	#	conditon_class,condition_details,condition_pc,
	#	pod_class,pod_details,pod_pc,
	#	statement_class,statement_details,statement_pc,
	#	subroutine_class,subroutine_details,subroutetine_pc,
	#	total_class,total_details,total_pc
	# TODO GET DISTRIBUTION
	my @header = qw/release distribution link
					branch_class branch_details branch_pc
					condition_class condition_details condition_pc
					pod_class pod_details pod_pc
					statement_class statement_details statement_pc
					subroutine_class subroutine_details sbroutine_pc
					total_class total_details total_pc/;
	print $fh join(",", @header ) . "\n";
	foreach my $release  (keys %{$data->{vals}} ) {

		my $line = [];
		push @$line, $release,
		push @$line, '';
		push @$line, $data->{vals}{$release}{link};

		foreach my $level1 ( qw/branch condition pod statement/ ) {
			foreach my $level2 ( qw/class details pc/ ) {
				push @$line, $data->{vals}{$release}{$level1}{$level2};
			} 			
		}
		print $fh join ( ",",@$line)."\n";
	}
	close $fh;
    print "\n\nWrote cpan_cover.csv output to $Options->{outputdir}/cpan_cover.csv\n";
}

sub write_html {
    my ($Options, $Template) = @_;
    my $d = $Options->{directory};
    chdir $d or die "Can't chdir $d: $!\n";

    my $results = read_results($Options);

    my $f = "$Options->{outputdir}/$Options->{outputfile}";
    print "\n\nWriting cpancover output to $f ...\n";

    my %vals;
    my $vars = {
        title   => "CPAN Coverage report",
        modules => [],
        vals    => \%vals,
    };

    for my $module (sort keys %$results) {
        my $dbdir = "$Options->{directory}/$module/cover_db";
        next unless -d $dbdir;
        chdir "$Options->{directory}/$module";
        print "Adding $module from $dbdir\n";

        eval {
            my $db = Devel::Cover::DB->new(db => $dbdir);
            # next unless $db->is_valid;

            my $criteria = $vars->{criteria} ||=
                           [ grep(!/path|time/, $db->all_criteria) ];
            $vars->{headers} ||=
                           [ grep(!/path|time/, $db->all_criteria_short) ];

            my %options = map { $_ => 1 } @$criteria;
            $db->calculate_summary(%options);

            push @{$vars->{modules}}, $module;
            $vals{$module}{link} = "$module/$Options->{outputfile}";

            for my $criterion (@$criteria)
            {
                my $summary = $db->summary("Total", $criterion);
                my $pc = $summary->{percentage};
                $pc = defined $pc ? sprintf "%6.2f", $pc : "n/a";
                $vals{$module}{$criterion}{pc}      = $pc;
                $vals{$module}{$criterion}{class}   = class($pc);
                $vals{$module}{$criterion}{details} =
                  ($summary->{covered} || 0) . " / " . ($summary->{total} || 0);
            }
        }
    }
    write_stylesheet($Options);
    $Template->process("summary", $vars, $f) or die $Template->error();
    write_csv($vars,$Options);
	
    print "done.\n";
    print "\n\nWrote cpancover output to $f\n";
}

sub class {
    my ($pc) = @_;
    $pc eq "n/a" ? "na" :
    $pc <    75  ? "c0" :
    $pc <    90  ? "c1" :
    $pc <   100  ? "c2" :
                   "c3"
}

sub get_cover {
    my ($module, $Options) = @_;

    print "\n\n\n**** Checking coverage of $module ****\n\n\n";

    my $d = "$Options->{directory}/$module";
    chdir $d or die "Can't chdir $d: $!\n";

    my $db = "$d/cover_db";
    print "Already analysed\n" if -d $db;

    my $out = "cover.out";
    unlink $out;

    my $test = !-e "$db/runs" || $Options->{force} ? " -test" : "";
    if ($test)
    {
        print "Testing $module\n";
        sys("$^X Makefile.PL >> $out 2>&1") unless -e "Makefile";
    }

    my $od = "$Options->{outputdir}/$module";
    my $of = $Options->{outputfile};
    my $timeout = 900;  # fifteen minutes should be enough

    if ($test || !-e "$od/$of" || $Options->{redo_html})
    {
        eval
        {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            sys("cover$test -report $Options->{report} " .
                "-outputdir $od -outputfile $of " .
                ">> $out 2>&1");
            alarm 0;
        };
        if ($@)
        {
            die unless $@ eq "alarm\n";   # propagate unexpected errors
            warn "Timed out after $timeout seconds!\n";
        }
    }

    my $results = read_results($Options);
    my $f = "$Options->{outputdir}/cover.results";

    $results->{$module} = 1;

    open my $fh, ">", $f or die "Can't open $f: $!\n";
    my $try;
    until (flock $fh, LOCK_EX)
    {
        die "Can't lock $f: $!\n" if $try++ > 60;
        sleep 1;
    }
    for my $mod (sort keys %$results)
    {
        print $fh "$mod $results->{$mod}\n";
    }
    close $fh or die "Can't close $f: $!\n";

    sys("cat $out") if -e $out;
}

sub sys {
    my ($command) = @_;
    print "$command\n";
    system $command;
}

sub run_cover {
    my $Options = shift;
    my $workers = $ENV{CPANCOVER_WORKERS} || 0;
    my @res = iterate_as_array
    (
        { workers => $workers },
        sub {
            eval {
              get_cover ($_[1], $Options);
              warn "\n\n\n[$_[1]]: $@\n\n\n" if $@;
          };
        },
        $Options->{module},
    );
    return $Options;
}

1;
