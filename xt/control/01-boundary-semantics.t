use strict;
use warnings;

use Test2::V0;
use Inline (
    C => 'DATA',
);

subtest 'av_fetch lval=1 is structurally mutating' => sub {
    my $av = [ qw(a b c) ];
    is $#$av, 2, 'array initially ends at index 2';

    is serial_av_fetch_growth($av, 5), 5,
        'serial av_fetch(..., 1) extends the AV to the requested index';
    is $#$av, 5,
        'Perl observes the grown AV after the C API call';

    pass 'therefore av_fetch(..., 1) is intentionally excluded from worker-thread readonly tests';
};

subtest 'HV iterator calls consume shared iterator state' => sub {
    my $hv = { alpha => 1, beta => 2, gamma => 3 };
    is serial_hv_iterator_advances($hv), 1,
        'two hv_iternext calls after one hv_iterinit consume distinct iterator positions';

    pass 'therefore hv_iterinit/hv_iternext are not treated as passive concurrent reads';
};

done_testing;

__DATA__
__C__

SV* serial_av_fetch_growth(AV *av, SSize_t index) {
    SV **slot = av_fetch(av, index, 1);
    if (!slot)
        return &PL_sv_undef;
    return newSViv((IV)av_len(av));
}

SV* serial_hv_iterator_advances(HV *hv) {
    HE *first;
    HE *second;

    hv_iterinit(hv);
    first  = hv_iternext(hv);
    second = hv_iternext(hv);

    return newSViv(first && second && first != second ? 1 : 0);
}

__END__
