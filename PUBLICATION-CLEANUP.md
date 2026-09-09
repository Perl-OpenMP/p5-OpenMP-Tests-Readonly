# Publication cleanup notes

This snapshot was prepared from the attached `p5-OpenMP-Tests-Readonly` research
repository for use alongside the arXiv/SPJ manuscripts.

The cleanup is intentionally conservative:

* preserves the original attached test files under `historical/original-attached/`;
* keeps the reported experiment scope at Perl 5.40.0 + GCC 12.2.0 + GNU libgomp;
* fixes the stale `private(str)` scalar-test typo;
* removes an accidental `SvLEN` assertion that reused the preceding `SvCUR`
  result, and compares concurrent `SvLEN` with a serial read of the same SV;
* removes misleading reference-type `SvTYPE` expectations unrelated to the
  paper's scalar-access claim;
* moves Perl allocation used to construct test return values out of OpenMP
  worker regions, so the harness isolates the read operation under test;
* activates an explicit `AvARRAY` read test matching the paper's AV table;
* uses ordinary `int` parameters at the Inline::C-visible AV index boundary and
  casts to Perl's `SSize_t` internally, avoiding wrapper-generation failures
  without changing the tested C API semantics;
* keeps AV structural growth outside worker regions;
* isolates `hv_fetch`/`hv_exists` from unrelated AV/SvPV reads by using fixed
  native C keys for the fixed test hash;
* stages `HE *` iterator results serially before testing concurrent
  `hv_iterval` reads;
* corrects the direct bucket traversal from `HvMAX(hash)` slots to
  `HvMAX(hash) + 1`, matching Perl's maximum-bucket-index semantics and the
  paper;
* corrects the misleading comment that `HvARRAY()` gives each thread its own
  bucket array: the threads share the bucket array but hold private local
  pointers to it;
* makes stress-result aggregation native/OpenMP-safe rather than relying on
  unrelated shared temporary-variable races;
* documents unsafe negative cases separately rather than leaving WIP/commented
  experiments in the passing suite.

An initial GitHub Actions run on 2026-09-08 exercised the cleaned harness with
Perl 5.40.0 and current compatible dependencies. In that run the scalar suite
completed 400 assertions successfully and the hash suite completed 128
assertions successfully, including the publication-shaped 1,000,000-iteration
hash stress configuration. The array suite stopped after its first two passing
assertions because Inline::C did not generate wrappers for helpers that exposed
`SSize_t` as a Perl-callable parameter type. This candidate changes only that
wrapper boundary to ordinary `int` parameters and casts to `SSize_t` inside the
C helpers. A fresh CI run is required before the snapshot is tagged for arXiv.

The 2026 CI environment is regression evidence, not an exact reproduction of
the historical paper environment: the paper reports Perl 5.40.0 built with GCC
12.2.0 and GNU libgomp, while the first GitHub Actions Perl 5.40.0 run reported
a Perl built with GCC 11.4.0 and a runner toolchain using GCC 13.3.0.

## CI additions

The publication snapshot now includes `.github/workflows/ci.yml`, a compact
Linux regression matrix, a full Perl 5.40.0 stress job, deterministic boundary
controls in `xt/control/`, and `script/report-environment.pl` so CI logs record
the actual compiler/module environment used by each run. These CI results are
explicitly separated from the historical Perl 5.40.0/GCC 12.2.0 experiment.
