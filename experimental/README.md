# Intentionally unsafe / negative cases

The passing OpenMP test suite under `t/` contains only access patterns intended
to remain read-only while OpenMP worker threads are active.

Two important negative cases discussed in the paper are deliberately *not* run
concurrently as CI tests:

* `av_fetch(av, index, 1)` may grow an AV. Concurrent calls that request growth
  are outside the read-only contract and can race on interpreter-managed AV
  state.
* `hv_iterinit()` / `hv_iternext()` advance iterator state associated with the
  HV itself. Multiple worker threads cannot use that shared iterator as
  independent concurrent cursors without coordination.

`xt/control/01-boundary-semantics.t` demonstrates these boundary properties in
a deterministic **serial** control: it shows that `av_fetch(..., 1)` grows an
AV and that successive `hv_iternext()` calls consume iterator positions. It
does not intentionally corrupt a Perl data structure or depend on a race being
observed.

The original exploratory files supplied for the research are preserved under
`historical/original-attached/`; they contain the disabled experiments and
comments from that investigation. They are retained for provenance and are not
part of the passing publication OpenMP suite.
