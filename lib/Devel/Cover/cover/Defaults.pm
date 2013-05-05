# Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::cover::Defaults;

use strict;
use warnings;

# VERSION

use base 'Exporter';
our @EXPORT_OK = qw(
    %defaults
    get_options
);
use Config;
use Getopt::Long;

our %defaults = (
    add_uncoverable_point    => [],
    annotation               => [],
    coverage                 => [],
    delete                   => undef,
    delete_uncoverable_point => [],
    gcov                     => $Config{gccversion},
    ignore                   => [],
    ignore_re                => [],
    launch                   => 0,
    make                     => $Config{make},
    report                   => "",
    report_c0                => 75,
    report_c1                => 90,
    report_c2                => 100,
    select                   => [],
    select_re                => [],
    summary                  => 1,
    uncoverable_file         => [".uncoverable", glob("~/.uncoverable")],
);

sub get_options {
    my $defaults = shift;
    my $Options = {};
    while (my ($k,$v) = each %{$defaults}) {
        $Options->{$k} = $v;
    }
    Getopt::Long::Configure("pass_through");
    die "Bad option" unless
        GetOptions($Options,            # Store the options in the Options hash.
                   "write:s" => sub
                   {
                       @$Options{qw( write summary )} = ($_[1], 0)
                   },
                   qw(
                       add_uncoverable_point=s
                       annotation=s
                       clean_uncoverable_points!
                       coverage=s
                       delete!
                       delete_uncoverable_point=s
                       dump_db!
                       gcov!
                       help|h!
                       ignore_re=s
                       ignore=s
                       info|i!
                       launch!
                       make=s
                       outputdir=s
                       report_c0=s
                       report_c1=s
                       report_c2=s
                       report=s
                       select_re=s
                       select=s
                       silent!
                       summary!
                       test!
                       uncoverable_file=s
                       version|v!
                     ));
    Getopt::Long::Configure("nopass_through");
    $Options->{report} ||= "html" unless exists $Options->{write};
    return $Options;
}

1;

__END__

=head1 NAME

Devel::Cover::cover::Defaults - Default values and options processing for F<cover>

=head1 SYNOPSIS

    use Devel::Cover::cover::Defaults qw(
        %defaults
        get_options
    );

=head1 DESCRIPTION

This module exports, on demand only, a hash of sensible default values for
F<cover> as well as function C<get_options()> to handle processing of
command-line options.

=head1 SUBROUTINES

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut
