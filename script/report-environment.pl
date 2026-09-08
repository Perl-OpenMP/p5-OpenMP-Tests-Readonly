#!/usr/bin/env perl
use strict;
use warnings;
use Config;

my @modules = qw(
    Alien::OpenMP
    Inline
    Inline::C
    OpenMP
    OpenMP::Environment
    OpenMP::Simple
    Test2::V0
);

print "Perl/OpenMP CI environment\n";
print "==========================\n";
printf "perl executable : %s\n", $^X;
printf "perl version    : %s\n", $^V;
printf "archname        : %s\n", $Config{archname} // '(unknown)';
printf "useithreads     : %s\n", $Config{useithreads} // '(unknown)';
printf "Config cc       : %s\n", $Config{cc} // '(unknown)';
printf "Config ccversion: %s\n", length($Config{ccversion} // '') ? $Config{ccversion} : '(not recorded)';
printf "Config gccversion: %s\n", length($Config{gccversion} // '') ? $Config{gccversion} : '(not recorded)';
printf "ccflags         : %s\n", $Config{ccflags} // '(unknown)';
printf "ldflags         : %s\n", $Config{ldflags} // '(unknown)';

print "\nPerl modules\n";
print "------------\n";
for my $module (@modules) {
    (my $file = "$module.pm") =~ s{::}{/}g;
    my $ok = eval { require $file; 1 };
    if (!$ok) {
        printf "%-22s NOT LOADABLE: %s\n", $module, $@;
        next;
    }
    no strict 'refs';
    my $version = ${"${module}::VERSION"};
    use strict 'refs';
    printf "%-22s %s\n", $module, defined($version) ? $version : '(no VERSION)';
}

if (eval { require Alien::OpenMP; 1 }) {
    print "\nAlien::OpenMP build flags\n";
    print "-------------------------\n";
    for my $method (qw(cflags libs)) {
        my $value = eval { Alien::OpenMP->$method() };
        $value = "ERROR: $@" if $@;
        printf "%-8s %s\n", $method, defined($value) ? $value : '(undef)';
    }
}
