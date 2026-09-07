# Intentionally unsafe / negative cases

The passing test suite under `t/` contains only access patterns intended to
remain read-only while OpenMP worker threads are active.

Two important negative cases discussed in the paper are deliberately *not*
run as automated tests:

* `av_fetch(av, index, 1)` may grow an AV. Concurrent calls that request growth
  are outside the read-only contract and can race on interpreter-managed AV
  state.
* `hv_iterinit()` / `hv_iternext()` advance iterator state associated with the
  HV itself. Multiple worker threads cannot use that shared iterator as
  independent concurrent cursors without coordination.

The original exploratory files supplied for the research are preserved under
`historical/original-attached/`; they contain the disabled experiments and
comments from that investigation. They are retained for provenance and are not
part of the passing publication test suite.
