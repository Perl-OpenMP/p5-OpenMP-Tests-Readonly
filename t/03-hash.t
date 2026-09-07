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
my $iterations  = $ENV{PERL_OPENMP_ITERATIONS}  || 1_000_000;

for my $want_num_threads (1 .. $max_threads) {
    note "$want_num_threads threads; $iterations stress iterations ...";

    $omp->env->omp_num_threads($want_num_threads);
    $omp->env->assert_omp_environment;

    is _check_num_threads(), $want_num_threads,
        'OpenMP runtime reports expected number of threads';

    my $hash = {
        key1 => 42,
        key2 => 84,
        key3 => 168,
        key4 => 336,
    };

    is test_hv_fetch($hash, $iterations), 4,
        'hv_fetch(..., lval=0) repeatedly reads all established keys';
    is test_hv_exists($hash, $iterations), 4,
        'hv_exists repeatedly observes all established keys';
    is test_hv_iterval($hash, $iterations), 4,
        'hv_iterval repeatedly reads values through HE pointers staged serially';
    is test_hv_keys($hash, $iterations), 4,
        'HvKEYS remains stable during concurrent read-only access';
    is test_hv_usedkeys($hash, $iterations), 4,
        'HvUSEDKEYS remains stable during concurrent read-only access';
    is test_hv_totalkeys($hash, $iterations), 4,
        'HvTOTALKEYS remains stable during concurrent read-only access';
    is test_hv_array($hash, $iterations), 4,
        'HvARRAY/HvMAX traversal repeatedly sees all entries in a stable hash';
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

SV* test_hv_fetch(HV *hash, int iterations) {
    static const char *keys[] = { "key1", "key2", "key3", "key4" };
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        int found = 0;
        for (int j = 0; j < 4; ++j) {
            SV **value = hv_fetch(hash, keys[j], 4, 0);
            if (value && *value)
                ++found;
        }
        if (found != 4)
            ++mismatches;
    }

    return newSViv(mismatches == 0 ? 4 : -1);
}

SV* test_hv_exists(HV *hash, int iterations) {
    static const char *keys[] = { "key1", "key2", "key3", "key4" };
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        int found = 0;
        for (int j = 0; j < 4; ++j) {
            if (hv_exists(hash, keys[j], 4))
                ++found;
        }
        if (found != 4)
            ++mismatches;
    }

    return newSViv(mismatches == 0 ? 4 : -1);
}

SV* test_hv_iterval(HV *hash, int iterations) {
    I32 expected = HvKEYS(hash);
    HE **entries;
    HE *he;
    I32 n_entries = 0;
    long failures = 0;
    PerlOMP_GETENV_BASIC

    entries = (HE**)malloc((size_t)expected * sizeof(*entries));
    if (!entries)
        croak("native allocation failed while staging HE pointers");

    /* Iterator state is advanced only on the calling thread. */
    hv_iterinit(hash);
    while ((he = hv_iternext(hash)) != NULL && n_entries < expected)
        entries[n_entries++] = he;

    #pragma omp parallel for reduction(+:failures)
    for (int i = 0; i < iterations; ++i) {
        for (I32 j = 0; j < n_entries; ++j) {
            if (hv_iterval(hash, entries[j]) == NULL)
                ++failures;
        }
    }

    free(entries);
    return newSViv(failures == 0 ? n_entries : -1);
}

SV* test_hv_keys(HV *hash, int iterations) {
    I32 expected = HvKEYS(hash);
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        if (HvKEYS(hash) != expected)
            ++mismatches;
    }
    return newSViv(mismatches == 0 ? expected : -1);
}

SV* test_hv_usedkeys(HV *hash, int iterations) {
    I32 expected = HvUSEDKEYS(hash);
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        if (HvUSEDKEYS(hash) != expected)
            ++mismatches;
    }
    return newSViv(mismatches == 0 ? expected : -1);
}

SV* test_hv_totalkeys(HV *hash, int iterations) {
    I32 expected = HvTOTALKEYS(hash);
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        if (HvTOTALKEYS(hash) != expected)
            ++mismatches;
    }
    return newSViv(mismatches == 0 ? expected : -1);
}

SV* test_hv_array(HV *hash, int iterations) {
    I32 expected = HvKEYS(hash);
    long mismatches = 0;
    PerlOMP_GETENV_BASIC

    #pragma omp parallel for reduction(+:mismatches)
    for (int i = 0; i < iterations; ++i) {
        I32 local_count = 0;
        HE **buckets = HvARRAY(hash); /* pointer to the shared, stable bucket array */
        STRLEN n_buckets = (STRLEN)HvMAX(hash) + 1;

        for (STRLEN j = 0; j < n_buckets; ++j) {
            HE *he = buckets[j];
            while (he) {
                ++local_count;
                he = HeNEXT(he);
            }
        }

        if (local_count != expected)
            ++mismatches;
    }

    return newSViv(mismatches == 0 ? expected : -1);
}

__END__
