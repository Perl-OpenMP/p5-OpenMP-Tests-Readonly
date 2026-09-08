# Perl/OpenMP read-only Perl C API stress tests

This repository contains the experimental harness associated with the paper
**"The Limits of Thread-Safety in the Perl C API Using OpenMP"**.

The purpose is deliberately narrow: stress selected Perl C API read operations
from native OpenMP worker threads while the referenced Perl data structures are
already established and are not being structurally modified.

## Experimental scope reported in the paper

The experimental claims in the paper are tied to:

* Perl **5.40.0**
* GCC **12.2.0**
* GNU **libgomp**
* thread counts **1 through 16**

Later releases and portability work in `Alien::OpenMP`, `OpenMP::Environment`,
`OpenMP::Simple`, `OpenMP`, or `perlomp` do **not** imply that the Perl C API
experiments were repeated with newer Perl releases, newer GCC releases, Clang,
Windows, macOS, FreeBSD, or other OpenMP runtimes.

The original research repository did not record a complete lockfile of the CPAN
module versions installed when the experiments were first run. The exact
original test files are therefore retained under `historical/original-attached/`
for provenance rather than pretending that current CPAN versions reproduce the
historical software environment exactly.

## Publication harness

The passing tests in `t/` preserve the operations studied in the paper while
removing unrelated worker-thread mutation from the harness itself. In
particular, Perl scalar/array allocation used to return test results now occurs
after OpenMP worker regions have completed. The hash tests also stage iterator
state serially when testing `hv_iterval`, and the `HvARRAY` test uses the
correct bucket count, `HvMAX(hv) + 1`.

| Paper result area | Test file | Principal operations |
| --- | --- | --- |
| Scalars (SV) | `t/01-scalar.t` | `SvPV`, `SvIV`, `SvNV`, `SvTRUE`, `SvTYPE`, `SvCUR`, `SvLEN`, `SvREFCNT` |
| Arrays (AV) | `t/02-array.t` | `av_len`, `av_fetch(..., 0)`, `av_exists`, `AvFILLp`, `AvARRAY` |
| Hashes (HV) | `t/03-hash.t` | `hv_fetch(..., 0)`, `hv_exists`, `hv_iterval`, `HvKEYS`, `HvARRAY`, `HvMAX` |

`hv_iterinit`/`hv_iternext` and growing `av_fetch(..., 1)` are discussed as
negative cases and are not executed by the passing suite; see
`experimental/README.md`.

## Prerequisites

The current harness expects the Perl+OpenMP stack and Inline::C. With cpanminus:

```sh
cpanm --installdeps .
```

That command installs *current compatible dependencies*. It is useful for
running the cleaned harness today; it is not a claim that those versions were
used for the historical experiment reported in the paper.

## Run

For the publication defaults:

```sh
prove -lv t
```

The defaults request OpenMP thread counts 1 through 16. The hash test performs
1,000,000 stress iterations per requested thread-count setting.

For a quick smoke run without changing the source:

```sh
PERL_OPENMP_MAX_THREADS=4 \
PERL_OPENMP_ITERATIONS=10000 \
prove -lv t
```

## Interpreting a pass

A pass means that the selected operations returned stable expected results
under this stress harness. It is **not** a general guarantee that the Perl C API
is thread-safe, nor that an operation is safe if another thread can mutate,
resize, rehash, autovivify, or otherwise change the structure being observed.
The paper's claims are intentionally scoped to the tested access patterns and
historical environment above.

## Reproducibility and publication snapshot

Before citing a repository state from arXiv or the journal article, create an
immutable Git tag (for example `arxiv-v1`) at the exact commit containing the
paper-facing harness. Record that tag or commit in the arXiv metadata or paper
source if a permanent software citation is desired.

## License

Same terms as Perl 5 itself. See `LICENSE`.

## Continuous integration

GitHub Actions runs two complementary forms of CI:

1. **Smoke/regression matrix** -- current compatible dependencies on Perl
   5.40.0, 5.42, and 5.44, using a reduced four-thread/10,000-iteration stress
   run so regressions can be found quickly.
2. **Perl 5.40.0 full stress job** -- the publication-shaped defaults of one
   through sixteen OpenMP threads and 1,000,000 hash stress iterations. This
   heavier job runs on pushes to `master` and on manual workflow dispatch, not
   on every pull request.

Every CI job prints `perl -V`-equivalent compiler information, the installed
Perl+OpenMP module versions, `Alien::OpenMP` build flags, the runner GCC
version, and the resolved `libgomp` path before running tests. This is important
because CI images and CPAN releases change over time.

The Perl 5.40.0 CI job is **not described as an exact reproduction of the paper
environment unless its emitted environment record actually shows GCC 12.2.0
and otherwise matches the historical setup**. The paper's reported experiment
remains Perl 5.40.0 built with GCC 12.2.0 and GNU libgomp. CI on current GitHub
runners is regression/portability evidence unless that exact match is
established from the job log.

The deterministic controls under `xt/control/` do not intentionally trigger
concurrent corruption. Instead they demonstrate, serially, two important
boundary conditions used by the paper: `av_fetch(..., 1)` can grow an AV, and
`hv_iterinit`/`hv_iternext` consume iterator state. The normal OpenMP suite in
`t/` therefore exercises `av_fetch(..., 0)` and avoids sharing Perl's HV
iterator state between workers.
