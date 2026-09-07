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

No claim is made here that the cleaned snapshot was executed on the historical
paper environment inside the ChatGPT build container. The container lacks the
Perl+OpenMP CPAN stack. The active Perl files were syntax-checked with stubbed
imports, and their embedded C bodies were checked with GCC `-fopenmp
-fsyntax-only` against the available Perl 5.40 headers. A real `prove -lv t`
run should be performed after these files are placed in the project environment.
