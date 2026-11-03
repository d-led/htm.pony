# Results

Every number on this page was written by the benchmark that measured it. The
measurement examples print their tables twice: once as text for a terminal,
which is pinned in `test/fixtures/studies/` and fails CI when it moves, and once
as markdown after a `==== markdown ====` line. `scripts/studies.sh`, which CI
runs on every push, keeps that markdown in `docs/results/` and fails when it no
longer matches, so this page cannot say something the programs do not.

Nothing here was transcribed by hand, and nothing here is a screenshot: the
tables are the programs' own output and the charts are
[mermaid](https://mermaid.js.org/syntax/xyChart.html) blocks those same programs
build from the same rows.

## Is a memory better than guessing?

Three streams, four methods asked at every step which columns it expects. The
number kept is the share of columns that arrived unannounced, so nought is
perfect and one is a method that expected nothing that happened.

--8<-- "results/prediction-baselines.md"

## How far does a picture fingerprint drift?

Five pictures built in code, each distorted five ways. The last row of each
table is the yardstick: the distance between two *different* pictures. A
distortion costs a hash little when its figure is well below that one.

--8<-- "results/image-robustness.md"

## The older studies

These four print their numbers as an aligned table rather than as a markdown
one: the pipeline that publishes them is in place, so converting each to a
table and a chart is a change to that study and nothing else.

## What cost what: the pooler's settings

--8<-- "results/pooler-settings-value.md"

## What boosting is worth

--8<-- "results/boosting-value.md"

## What a learned pooler gives a memory

--8<-- "results/pooler-training-value.md"

## What a learned pooler is worth to a damaged sequence

--8<-- "results/sequence-training-value.md"

## What is not here yet

The corpus benchmarks - `image-retrieval` and the images it downloads - are not
pinned, because the corpus is not stored in this repository: they print their
numbers when run, and `scripts/fetch-images.sh` is what puts a corpus on a disk
for them. The four older studies print their tables as text, and their markdown
is the next thing to wire up in the same way.
