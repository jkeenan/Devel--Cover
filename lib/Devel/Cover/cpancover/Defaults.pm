# Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::cpancover::Defaults;

use strict;
use warnings;

# VERSION

use base 'Exporter';
our @EXPORT_OK = qw(
    %defaults
    get_options
);
use Cwd ();
use Getopt::Long;
use Pod::Usage;

our %defaults = (
    collect      => 1,
    directory    => Cwd::cwd(),
    force        => 0,
    module       => [],
    report       => "html_basic",
);

sub get_options {
    my $defaults = shift;
    my $Options = {};
    while (my ($k,$v) = each %{$defaults}) {
        $Options->{$k} = $v;
    }
    die "Bad option" unless
        GetOptions($Options, # Store the options in the Options hash.
               qw(
                   collect!
                   directory=s
                   force!
                   help|h!
                   info|i!
                   module=s
                   outputdir=s
                   outputfile=s
                   redo_cpancover_html!
                   redo_html!
                   report=s
                   version|v!
                )
    );

    return $Options;
}

1;

__END__

=head1 NAME

Devel::Cover::cpancover::Defaults - Default values and options processing for
F<cpancover>

=head1 SYNOPSIS

    use Devel::Cover::cpancover::Defaults qw(
        %defaults
        get_options
    );

=head1 DESCRIPTION

This module exports, on demand only, a hash of sensible default values for
F<cpancover> as well as function C<get_options()> to handle processing of
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
