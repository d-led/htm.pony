# Handoff

Everything a new pair of hands needs: where this stands, what is left in the order it
should be done, what was decided deliberately, and the things that waste a day if nobody
says them out loud. Written 2026-11-02 at `24c9fea`.

The [roadmap](roadmap.md) says *why* the project exists and in what order the goals were
set. This page says *what is next* and *how to work here*.

## Where it stands

An actor-native HTM/CLA in Pony, ported from the Go reference
([htm-community/htm](https://github.com/htm-community/htm), MIT, Copyright 2014 Zac
Gross), with `htm.java`, `htm.core` and the NuPIC line read beside it where they say
something the Go one does not. This library is MPL-2.0.

| | state |
| --- | --- |
| Dense and sparse binary matrices, grid topology | done, the Go tests translated |
| Scalar, category, date, random distributed encoders | done, tested |
| Grid cell encoder | done, implemented from the `htm.core` algorithm |
| SimHash document encoder | done, own digest instead of SHAKE256 |
| Spatial pooler, permanence learning, boosting | done, in process and on actors |
| Temporal memory: cells, segments, prediction, bursts | done, in process and on actors |
| Classification: `SDRClassifier`, `PredictionClassifier` | done |
| Streaming anomaly score and its likelihood | done, in process and on actors (`AnomalyStream`) |
| **CLA temporal pooler** | **not ported** |
| Graph as one SDR | not written |

Verification at that commit: **172 tests green**, 16 examples run, `mkdocs build --strict`
clean, CI and Pages green, `studies` artifact byte-identical to a local run.

## How to verify a change

```sh
export PATH="$HOME/.local/share/ponyup/bin:$PATH"      # fresh shells do not have ponyc

cd test && corral run -- ponyc --debug && ./test       # the suite
./examples/run-all.sh                                  # every example, from the repo root
python3 scripts/api-reference.py                       # regenerate the API reference
./.venv-docs/bin/mkdocs build --strict                 # docs, warnings are errors
./scripts/studies.sh                                   # the three measured studies
cd microbenchmarks && corral run -- ponyc              # never --debug here
~/go/bin/actionlint .github/workflows/*.yml            # the workflows
```

Two rules that keep the repository honest, both enforced by tests:

- **One process and actors must agree exactly.** `temporal_region_test`,
  `anomaly_stream_test` and the pooler tests compare an actor answer with the in-process
  one, not with a stored expectation. If a change makes them disagree, the difference is
  the bug, not the test.
- **The studies are pinned.** `scripts/studies.sh` diffs against
  `test/fixtures/studies/*.txt` and prints the `cp` command to accept a new baseline. A
  changed number is a claim that behaviour changed; CI refuses until somebody brings the
  fixture with it.

## What is left, in the order to do it

### 1. The CLA temporal pooler — the largest piece, the reason the port exists

- Reference: `/Users/dmitryledentsov/src/htm/temporalPooler.go`, ~2 150 lines, with
  `temporalPooler_test.go`, `temporalPoolerPrint.go`, `temporalPoolerStats.go` beside it.
- What it adds: instead of one burst per unpredicted step, a stable, hierarchically
  pooled representation per node, with unions of child patterns — the thing that makes a
  CLA rather than a plain sequence memory.
- Do not port it in one commit. Slice it in this order and keep the suite green at every
  step: (a) the node/cell data model and its state transitions; (b) the sequence-of-
  patterns plumbing that the existing `TemporalMemory` shares; (c) the pooling pass;
  (d) the actor form only once the in-process one answers what the reference answers.
- Done looks like: the reference's own test cases translated into `test/`, the in-process
  pooler green, then an actor form with the same answers, then a page under `docs/`.

### 2. Give the temporal region the two things the pooler already has

Documented in [actors](actors.md#what-is-missing) and still true:

- **No deadline.** It waits for every shard on both passes, so one slow band stalls a
  step. The pooler's deadline-and-one-retry is the worked example to copy.
- **No `reconfigure`.** Shards cannot be replaced once the region is built.

The catch that makes this less trivial than it looks is written down there: a prediction
needs *all* the bands, so "decide without the missing shard" is not obviously meaningful.
Decide what a region with a missing band should answer before writing it.

### 3. Multi-step prediction

`PredictionClassifier` answers "what comes next". The Zeesoft ZDK classifier (see the
music section) takes an array of steps, 0 meaning classify now and n meaning predict n
steps ahead. Ours has the SDR classifier underneath, so this is a small extension rather
than new machinery: keep per-step count tables, and let a caller ask for step k.

### 4. A combiner for two SDRs

There is no way to merge two representations — everything that composes fields either
concatenates offsets by hand (the date encoder) or votes over the whole vector (SimHash).
The ZDK `Merger` is the shape: concatenate, subsample to a maximum number of on bits, or
distort. This is the missing piece for encoding "context + content" as one SDR, which is
what the music project below needs first.

### 5. A fixed-width category encoder

`CategoryEncoder` gives each label a contiguous block, so the width grows with the labels
and unknown labels are refused. `SDRCategoryEncoder` (in `htm.java` and `nupic`) is the
other shape: fixed `n`, `w` random bits per label, labels added as they are met, an
unknown slot. Both are legitimate; ours is documented as the closed-set one. Write the
open-set one when something needs it — most likely a stream of labels of unknown number.

### 6. A graph as one SDR

A graph — nodes and the edges between them — encoded as a single representation. Nothing
does this here and nothing in the references does it either, so it is design work, not a
port. Two encoders that were originally mistaken for it (grid cells, SimHash) are done and
are not it.

### 7. Smaller, already-diagnosed

- **Anomaly likelihood has no red/yellow filter.** Deliberate — it is a display decision —
  but a caller that wants one now has to write it.
- **Anomaly likelihood on a flat stream reads oddly.** When every score is exactly `0.0`,
  the fitted spread sits on its floor and a zero can come out at 0.95. The number is
  arithmetically right and practically useless; either document it where the likelihood is
  described or give the spread floor a better story. Relevant when a demo quotes it — the
  `anomaly-on-actors` example prints scores only, for this reason.
- **One pooler is one coordinator**, and its retry is one more deadline rather than a
  backoff. Both recorded in [actors](actors.md#what-is-missing); neither is a bug, both are
  limits somebody may want to lift.

## Decisions already made — do not reverse them silently

- **Licence: MPL-2.0.** The Go reference is MIT and is named in the README. `htm.core` and
  AI-909 are **AGPL-3.0**: read them and write the algorithm from their account of it,
  never transcribe. This is why the grid cell and SimHash encoders produce different bits
  from those libraries, and why their golden-bits tests are deliberately not ported — they
  pin numpy's and SHAKE256's numbers, not the encoding.
- **No locks, anywhere.** The actor path is one owner per piece of state and messages
  between them. If a design needs a lock, the design is wrong for this library.
- **An actor cannot refuse a message**, so behaviours are total: a column the memory was
  not built for is ignored, a region with no shards answers with nothing active. Failures
  before construction happen in partial `new create`, whose parameters are validated by
  the caller.
- **The anomaly detector does not train the pooler.** The memory predicts over the pooler's
  representation; a representation that kept moving would move the thing being learned.
  Same rule on the actor path.
- **Encoders return whatever the consumer can use**: a dense `Array[Bool]` when the vector
  *is* the representation (scalar, category, date, SimHash), active indices when the
  representation is a set of addressing cells (grid cells).
- **Deliberately not ported from the Go spatial pooler**: `updateInhibitionRadius` (the
  radius is configuration here, and also the radius `local` inhibition searches) and
  `stripNeverLearned` (it makes a freshly built pooler answer nothing). Both explained in
  [spatial pooler](spatial-pooler.md#what-is-not-ported). Do not "fix" these without
  deciding to change the behaviour they protect.
- **`deps/sagittarius` was deleted** — it had no licence file and the date encoder does its
  own calendar arithmetic. Dependencies are the Pony stdlib plus a vendored public-domain
  `stb_image`.
- **The image encoder is a demonstration, not the main line.** It exists to show the
  pipeline handling a representation that arrives as pixels. Do not build classification
  claims on it.

## Traps

- **`git commit -m` with backticks in the message**: zsh executed them once and the pushed
  commit `97e8936` reads "taken from it was , in - a function…". History is not rewritten.
  Use `git commit -F -` with a heredoc.
- **`ponyc` is not on the PATH** of a fresh shell. `export PATH="$HOME/.local/share/ponyup/bin:$PATH"`.
- **Never build the microbenchmarks with `--debug`** — the numbers are meaningless.
- **Example binaries are ignored one by one**, in `.gitignore`, on purpose: the pattern
  that would catch them ("everything in `examples/*` without a dot") would also silently
  ignore an extensionless source file. Adding an example means adding its binary there.
- **Docs are part of the change.** `mkdocs build --strict` fails on a broken link or a
  warning, and `scripts/api-reference.py` regenerates `docs/reference/api/`. The
  hand-written `docs/reference/modules.md` lists every source file — a new `.pony` file
  needs a section there.

## Pony things that cost a compile cycle each

All verified on ponyc 0.77.2:

- A `primitive` **cannot hold fields**; use a `fun` that returns the constant.
- NaN: the method is **`nan()`**, not `is_nan()` — and this `F64` says NaN **is equal to
  itself**, so `x != x` does not detect it.
- Inside a constructor, `this` is `tag` until every field is assigned: a helper called
  from `new create` cannot be a method of the same class. Put it on a `primitive`.
- **`_final` is a reserved method name** (the compiler's finaliser).
- `Array.pairs()` yields `(index, value)`; `Map.pairs()` yields `(key, value)`. Mixing them
  up gives a type error that reads as "argument type is USize".
- `Array[Bool](n)` sets **capacity**, not size.
- Partial constructors are `) ?` then `=>` on the next line; a `?` alone on its line is a
  syntax error.
- Several provides need parentheses: `actor X is (A & B)`.
- Actor constructor parameters must be sendable — that is why `AnomalyStream` takes the
  `AnomalyLikelihood` as `iso` and consumes it.
- NO named arguments, NO operator precedence (parens everywhere), `until`/`with`/`next`
  are keywords, parameter names cannot start with `_`, `Array` has no `eq` (use
  `BoolArray.are_equal` from `htm/util`), and an interface-typed field cannot be passed to
  a parameter of that interface type (inline the `match`).

## Where the details live

- `docs/` — the concepts, guides and the roadmap; `docs/reference/modules.md` lists every
  file with what it is and which test covers it.
- `docs/examples.md` — every example with its measured output; the numbers there come from
  a run, not from memory.
- `/memories/repo/build.md` — build facts, the same Pony traps, what each encoder settled
  on.
- `/memories/music-htm-backlog.md` — the music project this is eventually for.
- `/memories/pony.md` (user memory) — Pony language notes; `pony-ref` skill is the full
  reference.

## The music project this is for (not started; do not start it unasked)

The reason the encoders and the anomaly score matter: a drum/melody generator driven by
this library. Four references were collected and written up in
`/memories/music-htm-backlog.md`; the operative parts:

- **MidiDreamer** (DyzLecticus/Zeesoft `V5.0/ZDBD`, Java): rhythm + pattern number become
  "context" SDRs; an instrument pattern is split into three groups (drums /
  percussion+bass+octave+note / stab); each group is merged with the context, pooled
  (32×32, 20 on bits), given to a temporal memory (32×32×16), and read by **one classifier
  per instrument**. Trains in ~41 s, ~0.989 accuracy, then generates by walking the trained
  network. The encoding scheme is the idea worth taking; it needs item 4 above (a
  combiner).
- **ZDK** (same author, the library under it): `predictSteps`, `Merger`, apical feedback in
  the temporal memory, a `Network` that saves and loads as text files. Also the number to
  beat: 27 ms per SDR through SP+TM+CL.
- **AI-909** (TaylorPeer, Java/Spring Boot, **AGPL-3.0**): a 909-style drum machine on HTM,
  worth reading for the loop and the UX (memory banks, learn button, endless generation),
  never for copying.
- **Midi2Vec** (TaylorPeer, Python): MIDI → doc2vec (vector size 8, window 5) → LSTM over
  Bach chorales. A baseline an SDR representation should beat, not an architecture.
