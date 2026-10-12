# Contributing to xmojo

## The gate

Every change must keep the gate green, and the gate must be able to fail:

```
pixi run gate   # unit tests, tool builds, tools/oracle.py against expat (2 seeds x 2015 documents), and the --negative control
```

A pull request that changes parsing adds what it needs to `tools/oracle.py` (a generator case, or
a fixture in `tests/fixtures/`) and a regression case in `tests/`. A test that cannot go red is
not a test; the oracle's `--negative` run is there to show that it can.

A pull request that claims a speedup or a memory saving shows `tools/ab.sh` (interleaved medians)
or `tools/bench.sh` output before and after, from binaries built from the same benchmark source.

## Sign-off (DCO)

Commits are signed off under the [Developer Certificate of Origin](https://developercertificate.org/) 1.1:

```
git commit -s
```

The `Signed-off-by:` line certifies that you wrote the change or have the right to submit it
under the Apache-2.0 license. No CLA.

## Style

- Mojo is the implementation language. Python is allowed only as an oracle or generator, kept in
  `tools/` next to what it checks, pinned through `pixi.lock`.
- One fact, one home: numbers live in the file that produced them and are linked, not restated.
- `src/xmojo/html_entities.mojo` is generated: change `tools/gen_entities.py`, not the output.
- No attribution trailers other than `Signed-off-by`.

## Copyright

Contributions are licensed under Apache-2.0. New source files carry the header line used
throughout the repository. The copyright holder for the project is amarbaro.org.
