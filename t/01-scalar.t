use strict;
use warnings;

use Test2::V0;
use OpenMP;
use Inline (
    C    => 'DATA',
    with => qw/OpenMP::Simple/,
);

my $omp = OpenMP->new;
my $max_threads = $ENV{PERL_OPENMP_MAX_THREADS} || 16;

for my $want_num_threads (1 .. $max_threads) {
    note "$want_num_threads threads ...";

    $omp->env->omp_num_threads($want_num_threads);
    $omp->env->assert_omp_environment;

    is _check_num_threads(), $want_num_threads,
        'OpenMP runtime reports expected number of threads';

    my $input = 'Hello, OpenMP::Simple!';
    is testSvPV($input), $input,
        'SvPV reads an established string consistently across worker threads';

    is testSvIV($want_num_threads), $want_num_threads,
        'SvIV reads an established integer consistently across worker threads';

    my $double = 42.42;
    is testSvNV($double), $double,
        'SvNV reads an established numeric value consistently across worker threads';

    for my $case (
        [ undef,   0, 'undef is false' ],
        [ '',      0, 'empty string is false' ],
        [ '0',     0, 'string 0 is false' ],
        [ '0E0',   1, '0E0 is true' ],
        [ 0,       0, 'integer 0 is false' ],
        [ 1,       1, 'integer 1 is true' ],
        [ -1,      1, 'negative integer is true' ],
        [ 'Hello', 1, 'non-empty string is true' ],
        [ ' ',     1, 'space is true' ],
        [ [],      1, 'array reference is true' ],
        [ {},      1, 'hash reference is true' ],
    ) {
        is testSvTRUE($case->[0]), $case->[1], "SvTRUE: $case->[2]";
    }

    like testSvTYPE(undef),   qr/Undefined/, 'SvTYPE identifies undef scalar state';
    like testSvTYPE(42),      qr/Integer/,   'SvTYPE identifies integer scalar state';
    like testSvTYPE(42.42),   qr/Float/,     'SvTYPE identifies numeric scalar state';
    like testSvTYPE('Hello'), qr/String/,    'SvTYPE identifies string scalar state';

    my $cur_string = 'this string is 33 characters long';
    is testSvCUR($cur_string), 33,
        'SvCUR reports the expected current string length';

    my $len_string = "this string has embedded padding\0\0\0";
    is testSvLEN($len_string), serialSvLEN($len_string),
        'SvLEN concurrent read matches a serial SvLEN read of the same SV';

    my $scalar = 'Hello, World!';
    my $ref1 = \$scalar;
    my $ref2 = \$scalar;
    my $ref3 = \$scalar;

    is testSvREFCNT($scalar), serialSvREFCNT($scalar),
        'SvREFCNT concurrent read matches serial reference count';
    $ref3 = undef;
    is testSvREFCNT($scalar), serialSvREFCNT($scalar),
        'SvREFCNT remains consistent after dropping one reference';
    $ref2 = undef;
    is testSvREFCNT($scalar), serialSvREFCNT($scalar),
        'SvREFCNT remains consistent after dropping two references';
    $ref1 = undef;
    is testSvREFCNT($scalar), serialSvREFCNT($scalar),
        'SvREFCNT remains consistent after dropping all extra references';
}

done_testing;

__DATA__
__C__

int _check_num_threads() {
    int ret = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        #pragma omp single
        ret = omp_get_num_threads();
    }
    return ret;
}

SV* testSvPV(SV* input) {
    const char *observed = NULL;
    STRLEN observed_len = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        STRLEN local_len = 0;
        const char *local = SvPV(input, local_len);
        #pragma omp single
        {
            observed = local;
            observed_len = local_len;
        }
    }

    /* Perl allocation occurs after the worker region. */
    return newSVpv(observed, observed_len);
}

SV* testSvIV(SV* input) {
    IV observed = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        IV local = SvIV(input);
        #pragma omp single
        observed = local;
    }
    return newSViv(observed);
}

SV* testSvNV(SV* input) {
    NV observed = 0.0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        NV local = SvNV(input);
        #pragma omp single
        observed = local;
    }
    return newSVnv(observed);
}

SV* testSvTRUE(SV* input) {
    int observed = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        int local = SvTRUE(input) ? 1 : 0;
        #pragma omp single
        observed = local;
    }
    return newSViv(observed);
}

SV* testSvTYPE(SV* input) {
    int observed = SVt_NULL;
    const char *type_name = "Unknown";
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        int local = SvTYPE(input);
        #pragma omp single
        observed = local;
    }

    switch (observed) {
        case SVt_NULL: type_name = "Undefined (SVt_NULL)"; break;
        case SVt_IV:   type_name = "Integer (SVt_IV)";    break;
        case SVt_NV:   type_name = "Float (SVt_NV)";      break;
        case SVt_PV:   type_name = "String (SVt_PV)";     break;
        default:       type_name = "Other";                break;
    }
    return newSVpv(type_name, 0);
}

SV* testSvCUR(SV* input) {
    STRLEN observed = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        STRLEN local = SvCUR(input);
        #pragma omp single
        observed = local;
    }
    return newSVuv((UV)observed);
}

SV* testSvLEN(SV* input) {
    STRLEN observed = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        STRLEN local = SvLEN(input);
        #pragma omp single
        observed = local;
    }
    return newSVuv((UV)observed);
}

SV* serialSvLEN(SV* input) {
    return newSVuv((UV)SvLEN(input));
}

SV* testSvREFCNT(SV* input) {
    U32 observed = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel
    {
        U32 local = SvREFCNT(input);
        #pragma omp single
        observed = local;
    }
    return newSVuv((UV)observed);
}

SV* serialSvREFCNT(SV* input) {
    return newSVuv((UV)SvREFCNT(input));
}

__END__
