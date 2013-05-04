# Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::cover::Functions;

use strict;
use warnings;

# VERSION

#use Cwd 'abs_path';
use base 'Exporter';
our @EXPORT_OK = qw(
    get_options
    delete_db
    test_command
    gcov_args
    mb_test_command
    mm_test_command
    run_gcov
    prepare_db
    launch
    new
);
use File::Spec;
use Devel::Cover::DB;
use File::Find;
use File::Path;
use Getopt::Long;
use Pod::Usage;

sub get_options
{
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

sub new {
    my $config = shift;
    my $data = {};
    while (my ($k,$v) = each %{$config}) {
        $data->{$k} = $v;
    }
    $Devel::Cover::Silent = 1 if $data->{silent};
    
    my $format = "Devel::Cover::Report::\u$data->{report}";
    if (length $data->{report})
    {
        eval ("use $format");
        if ($@)
        {
            print "Error: $data->{report} ",
                  "is not a recognised output format\n\n$@";
            return;
        }
    }
    
    $format->get_options($data) if $format->can("get_options");
    $data->{format} = $format;
    
    $data->{annotations} = [];
    for my $a (@{$data->{annotation}})
    {
        my $annotation = "Devel::Cover::Annotation::\u$a";
        eval ("use $annotation");
        if ($@)
        {
            print "Error: $a is not a recognised annotation\n\n$@";
            return;
        }
        my $ann = $annotation->new;
        $ann->get_options($data) if $ann->can("get_options");
        push @{$data->{annotations}}, $ann;
    }
    
    # XXX: not working: should be Devel::Cover's release (CPAN) $VERSION,
    # e.g., 1.02

    if ($data->{version}) {
        print "$0 version " . __PACKAGE__->VERSION . "\n";
        return;
    }
    if ($data->{help}) {
        pod2usage(-verbose => 1);
        return;
    }
    if ($data->{info}) {
        pod2usage(-verbose => 2);
        return;
    }
    
    my $dbname = File::Spec->rel2abs(@ARGV ? shift @ARGV : "cover_db");
    die "Can't open database $dbname\n"
        if !$data->{delete} && !$data->{test} && !-d $dbname;
    $data->{dbname} = $dbname;
    
    $data->{outputdir} = $dbname unless exists $data->{outputdir};
    my $od = File::Spec->rel2abs($data->{outputdir});
    $data->{outputdir} = $od if defined $od;
    mkpath($data->{outputdir}) unless -d $data->{outputdir};

    return $data;
}

sub delete_db
{
    my $self = shift;
    my @dbs_to_delete = ($self->{dbname}, @_);
    for my $del (@dbs_to_delete)
    {
        my $db = Devel::Cover::DB->new(db => $del);
        unless ($db->is_valid)
        {
            print "Devel::Cover: $del is an invalid database - ignoring\n"
                unless $self->{silent};
            next;
        }
        print "Deleting database $del\n" if $db->exists && !$self->{silent};
        $db->delete;
        rmtree($del);
    }
}


# Decide whether to run ./Build test or make test
sub test_command {
    my $config = shift;
    -e "Build"
        ? mb_test_command($config)
        : mm_test_command($config);
}

# Compiler arguments necessary to do a coverage run
sub gcov_args() { "-fprofile-arcs -ftest-coverage" }

# Test command for MakeMaker
sub mm_test_command
{
    my $config = shift;
    my $test = "$config->{make} test";

    if ($config->{gcov})
    {
        my $o = gcov_args();
        $test .= qq{ "OPTIMIZE=-O0 $o" "OTHERLDFLAGS=$o"};
    }

    $test
}

# Test command for Module::Build
sub mb_test_command
{
    my $config = shift;
    my $test = './Build test';

    if ($config->{gcov})
    {
        my $o = gcov_args();
        $test .= qq{ "--extra_compiler_flags=-O0 $o" "--extra_linker_flags=$o"};
    }

    $test
}

sub run_gcov {
    my $self = shift;
    my $gc = sub
    {
        return unless /\.(xs|cc?|hh?)$/;

        my ($name) = /([^\/]+$)/;

        # Don't bother running gcov if there's no index files.
        # Otherwise it's noisy.
        my $graph_file = $_;
        $graph_file =~ s{\.\w+$}{.gcno};
        return unless -e $graph_file;

        my @c = ("gcov", "-abc", "-o", $File::Find::dir, $name);
        print STDERR "cover: running @c\n";
        system @c;
    };
    File::Find::find({ wanted => $gc, no_chdir => 1 }, ".");
    my @gc;
    my $gp = sub
    {
        return unless /\.gcov$/;
        my $xs = $_;
        return if $xs =~ s/\.(cc?|hh?)\.gcov$/.xs.gcov/ && -e $xs;
        s/^\.\///;
        push @gc, $_;
    };
    File::Find::find({ wanted => $gp, no_chdir => 1 }, ".");
    if (@gc)
    {
        # Find the right gcov2perl based on this current script.
        require Cwd;
        my $path = Cwd::abs_path($0);
        my ($vol, $dir, $cover) = File::Spec->splitpath($path);
        my $gcov2perl = File::Spec->catpath($vol, $dir, 'gcov2perl');
        my @c = ($^X, $gcov2perl, "-db", $self->{dbname}, @gc);
        print STDERR "cover: running @c\n";
        system @c;
    }
}

sub prepare_db {
    my $self = shift;
    print "Reading database from $self->{dbname}\n" unless $self->{silent};
    my $db = Devel::Cover::DB->new
    (
        db               => $self->{dbname},
        uncoverable_file => $self->{uncoverable_file},
    );
    $db = $db->merge_runs;
    
    $db->add_uncoverable     ($self->{add_uncoverable_point}   );
    $db->delete_uncoverable  ($self->{delete_uncoverable_point});
    $db->clean_uncoverable if $self->{clean_uncoverable_points} ;
    return if @{$self->{add_uncoverable_point}}    ||
              @{$self->{delete_uncoverable_point}} ||
              $self->{clean_uncoverable_points};
    return $db;
}

sub launch {
    my ($config, $format) = @_;
    if ($format->can("launch"))
    {
        $format->launch($config);
        return 1;
    }
    else
    {
        print STDERR "The launch option is not available for the ",
                     "$config->{report} report.\n";
        return 0;
    }
}

1;

__END__

=head1 NAME

Devel::Cover::cover::Functions - Functions called within F<cover>

=head1 SYNOPSIS

 use Devel::Cover::cover::Functions qw(
 );

=head1 DESCRIPTION

This module holds functions called by F<cover>.

=head1 SUBROUTINES

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut
