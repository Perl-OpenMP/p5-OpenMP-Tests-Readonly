# Original attached research harness

These files are preserved byte-for-byte from the repository snapshot supplied
when the publication cleanup was performed in September 2026.

They document the exploratory state of the research harness, including disabled
negative tests and work-in-progress comments. The cleaned tests in the top-level
`t/` directory isolate the same read operations more carefully by keeping Perl
allocation and other interpreter-managed mutation outside OpenMP worker regions.
