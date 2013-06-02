package Devel::Cover::cpancover;
use strict;
use warnings;
use Data::Dumper ();  # no import of Dumper (use Devel::Cover::Dumper if needed)
use Fcntl ":flock";
use base qw( Exporter );
our @EXPORT_OK = qw(
    read_results
);

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

1;
