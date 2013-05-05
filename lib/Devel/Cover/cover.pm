# Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::cover;

use strict;
use warnings;

# VERSION

use Data::Dumper ();  # no import of Dumper (use Devel::Cover::Dumper if needed)
use Devel::Cover::DB;
use File::Find;
use File::Path;
use File::Spec;
use Getopt::Long;
use Pod::Usage;

sub new {
    my $class = shift;
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
    
    # XXX: -version not working:
    # should be Devel::Cover's release (CPAN) $VERSION,
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

    return bless $data, $class;
}

sub delete_db {
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

sub run_test {
    my $self = shift;
    my @ARGV = @_;
    # TODO - make this a little robust
    # system "$^X Makefile.PL" unless -e "Makefile";
    $self->delete_db(@ARGV) unless defined $self->{delete};
    my $env_db_name = $self->{dbname};
    $env_db_name =~ s/\\/\\\\/g if $^O eq 'MSWin32';
    my $extra = "";
    $extra .= ",-coverage,$_" for @{$self->{coverage}};
    $extra .= ",-ignore,$_"
        for @{$self->{ignore_re}},
            map quotemeta glob, @{$self->{ignore}};
    $extra .= ",-select,$_"
        for @{$self->{select_re}},
            map quotemeta glob, @{$self->{select}};

    $self->{$_} = [] for qw( ignore ignoring select select_re );

    local $ENV{ -d "t" ? "HARNESS_PERL_SWITCHES" : "PERL5OPT" } =
        ($ENV{DEVEL_COVER_TEST_OPTS} || "") .
        " -MDevel::Cover=-db,$env_db_name$extra";

    my $test = $self->test_command();

    # touch the XS, C and H files so they rebuild
    if ($self->{gcov})
    {
        my $t = $] > 5.7 ? undef : time;
        my $xs = sub { utime $t, $t, $_ if /\.(xs|cc?|hh?)$/ };
        File::Find::find({ wanted => $xs, no_chdir => 0 }, ".");
    }
    # print STDERR "$_: $ENV{$_}\n" for qw(PERL5OPT HARNESS_PERL_SWITCHES);
    print STDERR "cover: running $test\n";
    my $test_result = system $test || 0;
    $self->{report} ||= "html";
    return ($test_result);
}

# Decide whether to run ./Build test or make test
sub test_command {
    my $self = shift;
    -e "Build"
        ? $self->mb_test_command()
        : $self->mm_test_command();
}

# Compiler arguments necessary to do a coverage run
sub gcov_args() { "-fprofile-arcs -ftest-coverage" }

# Test command for MakeMaker
sub mm_test_command {
    my $self = shift;
    my $test = "$self->{make} test";

    if ($self->{gcov})
    {
        my $o = gcov_args();
        $test .= qq{ "OPTIMIZE=-O0 $o" "OTHERLDFLAGS=$o"};
    }
    return $test;
}

# Test command for Module::Build
sub mb_test_command {
    my $self = shift;
    my $test = './Build test';

    if ($self->{gcov})
    {
        my $o = gcov_args();
        $test .= qq{ "--extra_compiler_flags=-O0 $o" "--extra_linker_flags=$o"};
    }
    return $test;
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
    return unless defined($db);
    $self->{db} = $db;
    return 1;
}

sub merge_databases {
    my $self = shift;
    my @argv = @_;
    for my $merge (@argv)
    {
        print "Merging database from $merge\n" unless $self->{silent};
        my $mdb = Devel::Cover::DB->new(db => $merge);
        $mdb = $mdb->merge_runs;
        $self->{db}->merge($mdb);
    }
}

sub dump_db {
    my $self = shift;
    my $d = Data::Dumper->new([$self->{db}], ["db"]);
    $d->Indent(1);
    $d->Sortkeys(1) if $] >= 5.008;
    print $d->Dump;
    my $structure = Devel::Cover::DB::Structure->new(base => $self->{dbname});
    $structure->read_all;
    my $s = Data::Dumper->new([$structure], ["structure"]);
    $s->Indent(1);
    $s->Sortkeys(1) if $] >= 5.008;
    print $s->Dump;
    return 1;
}

sub write_db {
    my $self = shift;
    $self->{dbname} = $self->{write} if length $self->{write};
    print "Writing database to $self->{dbname}\n" unless $self->{silent};
    $self->{db}->write($self->{dbname});
}

sub prepare_summary {
    my $self = shift;
    $self->{coverage}    = [ $self->{db}->collected ] unless @{$self->{coverage}};
    $self->{show}        = { map { $_ => 1 } @{$self->{coverage}} };
    $self->{show}{total} = 1 if keys %{$self->{show}};

    $self->{db}->calculate_summary(map { $_ => 1 } @{$self->{coverage}});
}

sub second_prepare_db {
    my $self = shift;
    # TODO - The sense of select and ignore should be reversed to match
    # collection.
    
    my %f = map { $_ => 1 } (@{$self->{select}}
                             ? map glob, @{$self->{select}}
                             : $self->{db}->cover->items);
    delete @f{map glob, @{$self->{ignore}}};
    
    my $keep = sub
    {
        my ($f) = @_;
        return 0 unless exists $self->{db}->{summary}{$_};
        for (@{$self->{ignore_re}})
        {
            return 0 if $f =~ /$_/
        }
        for (@{$self->{select_re}})
        {
            return 1 if $f =~ /$_/
        }
        !@{$self->{select_re}}
    };
    @{$self->{file}} = sort grep $keep->($_), keys %f;
}

sub execute_summary {
    my $self = shift;
    $self->{db}->print_summary(
        $self->{file},
        $self->{coverage},
        {force => 1},
    );
    return 1;
}

sub execute_report {
    my $self = shift;
    $self->{format}->report($self->{db}, $self);
    return 1;
}

sub launch {
    my $self = shift;
    if ($self->{format}->can("launch"))
    {
        $self->{format}->launch($self);
        return 1;
    }
    else
    {
        print STDERR "The launch option is not available for the ",
                     "$self->{report} report.\n";
        return 0;
    }
}

1;

__END__



1;

__END__

=head1 NAME

Devel::Cover::cover - Functions called within F<cover>

=head1 SYNOPSIS

 use Devel::Cover::cover;

=head1 DESCRIPTION

This package provides methods called by F<cover>.

=head1 SUBROUTINES

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2013, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut
