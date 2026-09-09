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

    my $array_ref = [1 .. 1000];

    is test_av_len($array_ref), $#$array_ref,
        'av_len concurrent reads return the highest array index';

    is test_av_fetch($array_ref, 999, 0), $array_ref->[999],
        'av_fetch(..., lval=0) reads an existing value without requesting growth';

    is test_av_exists($array_ref, 999), 1,
        'av_exists observes an existing index';
    is test_av_exists($array_ref, 1000), 0,
        'av_exists observes a missing index without creating it';

    is test_av_fill_index($array_ref), $#$array_ref,
        'AvFILLp concurrent reads return the current fill index';

    is test_av_array_count($array_ref), scalar(@$array_ref),
        'AvARRAY concurrent reads see the established SV pointer vector';

    # Structural mutation is deliberately performed by Perl between native calls,
    # never concurrently with the worker reads under test.
    $array_ref->[1010] = 1000;
    is test_av_fill_index($array_ref), 1010,
        'AvFILLp observes a stable array after Perl-side growth has completed';
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

SV* test_av_len(SV* input) {
    AV *array;
    SSize_t observed = -1;
    PerlOMP_GETENV_BASIC

    if (!SvROK(input) || SvTYPE(SvRV(input)) != SVt_PVAV)
        return &PL_sv_undef;

    array = (AV*)SvRV(input);
    #pragma omp parallel
    {
        SSize_t local = av_len(array);
        #pragma omp single
        observed = local;
    }
    return newSViv((IV)observed);
}

SV* test_av_fetch(SV* array_ref, int index, int lval) {
    AV *array;
    SV *observed = NULL;
    PerlOMP_GETENV_BASIC

    if (!SvROK(array_ref) || SvTYPE(SvRV(array_ref)) != SVt_PVAV)
        return &PL_sv_undef;

    array = (AV*)SvRV(array_ref);
    SSize_t idx = (SSize_t)index;
    #pragma omp parallel
    {
        SV **fetched = av_fetch(array, idx, lval);
        SV *local = (fetched && *fetched) ? *fetched : NULL;
        #pragma omp single
        observed = local;
    }

    /* Copy the result only after all worker reads have completed. */
    return observed ? newSVsv(observed) : &PL_sv_undef;
}

SV* test_av_exists(SV* array_ref, int index) {
    AV *array;
    int observed = 0;
    PerlOMP_GETENV_BASIC

    if (!SvROK(array_ref) || SvTYPE(SvRV(array_ref)) != SVt_PVAV)
        return &PL_sv_undef;

    array = (AV*)SvRV(array_ref);
    SSize_t idx = (SSize_t)index;
    #pragma omp parallel
    {
        int local = av_exists(array, idx) ? 1 : 0;
        #pragma omp single
        observed = local;
    }
    return newSViv(observed);
}

SV* test_av_fill_index(SV* array_ref) {
    AV *array;
    SSize_t observed = -1;
    PerlOMP_GETENV_BASIC

    if (!SvROK(array_ref) || SvTYPE(SvRV(array_ref)) != SVt_PVAV)
        return &PL_sv_undef;

    array = (AV*)SvRV(array_ref);
    #pragma omp parallel
    {
        SSize_t local = AvFILLp(array);
        #pragma omp single
        observed = local;
    }
    return newSViv((IV)observed);
}

SV* test_av_array_count(SV* array_ref) {
    AV *array;
    SSize_t last;
    IV observed = -1;
    PerlOMP_GETENV_BASIC

    if (!SvROK(array_ref) || SvTYPE(SvRV(array_ref)) != SVt_PVAV)
        return &PL_sv_undef;

    array = (AV*)SvRV(array_ref);
    last = AvFILLp(array);

    #pragma omp parallel
    {
        IV local_count = 0;
        SV **local_vector = AvARRAY(array); /* shared vector, thread-local pointer */

        for (SSize_t i = 0; i <= last; ++i) {
            if (local_vector[i] != NULL)
                ++local_count;
        }

        #pragma omp single
        observed = local_count;
    }

    return newSViv(observed);
}

__END__
