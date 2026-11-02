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
| CLA temporal pooler | **done** - a step with and without pooling, inference and learning backtracking, a forecast several steps ahead, and the actor form; the diagnostics are deliberately not ported |
| Graph as one SDR | done, as a design - `GraphEncoder`: a node is a category, an edge is two nodes and a direction, a graph is the union |

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

Every item on this list is in as of the pooler's forecast: the CLA temporal
pooler in seven slices, the region's deadline and retry, multi-step prediction,
`SDRMerger`, the fixed-width category encoder, the graph encoder, and the smaller
things item 7 diagnoses. What each slice was held to, and which parts of the
reference were deliberately not ported, is written under it.

New work starts from the [roadmap](roadmap.md) and from what is still open in
[actors](actors.md#what-is-missing).

### 1. The CLA temporal pooler — the largest piece, the reason the port exists

**Slice (a), the data model, is in** (`temporal_pooler_config.pony`,
`cla_segment.pony`, `cla_cell.pony`, `cla_state.pony`, with a test file each):

- `TemporalPoolerConfig` - the reference's parameters, with the validation
  `NewTemporalPooler` did by panicking, and the fields it never read (`burnIn`) or
  that belong to printing left out. The two fixed-size limits are `0` for
  "unlimited" rather than `-1`.
- `ClaSegment` - a pooler segment answers two different questions: `activity`
  (how much of the state it reaches, however weak the synapses) and `active`
  (enough *connected* synapses to predict). Its tiered `duty_cycle` is ported,
  with one deliberate divergence at iteration zero where the reference divides by
  zero and gets an infinity.
- `ClaCell` and `ClaNode` - a cell's segments, `best_segment` with the
  reference's tie rule (the later of the equals), and the node that owns its
  cells.
- `CellState` and `CellConfidence` - what the learning pass and the inference pass
  each need: active/predicted now and at the step before, plus the cell and node
  confidences with the normalisation that makes them shares of the whole.

Nothing computes a step yet; that is (b). The reference's `isSequenceSeg` is
absent on purpose - the only value it is ever set to is `true`.

**Slice (b), the step, is in** (`temporal_pooler.pony`, `cla_segment_update.pony`,
and the learning-side methods of the segment and cell): `TemporalPooler.compute`
runs the inference pass (activate, then predict with confidences) and the learning
pass (judge the proposals queued last step, activate, decide whether the sequence
held, predict ahead and queue proposals), the tiered duty-cycle review, the
average input density, the age-based decay, and `reset`. The reference's own
`TestLearnPredict` is translated and green: five patterns, ten epochs, then four
steps of inference that predict the next pattern's ten nodes exactly. 211 tests
green (39 new across the two slices).

Two gaps were named here, and both are now in: **backtracking** (the reference
re-plays a step from an earlier input when a sequence is lost, below) and
**pooling** itself, which is (c).

**Slice (c), pooling, is in.** With `pooling` on, a cell that is predicted also
learns the state one step *before* the one that taught it - on the segment of its
node that matches that step, or on a new one - and a proposal whose node has not
fired yet is kept while the cell is still predicted, for as long as
`update_window` allows.

The measured consequence, and the test that states it: the pooler predicts the
next pattern **and the one after it**, because a pooled cell can be woken by a
longer context. Ten epochs of five patterns, then a window of one: twenty nodes
predicted, exactly the next two patterns. On the same seed and input a pooling
pooler also grows more segments than a plain one, which is the same fact seen
from the other side.

Before anyone tunes this: with the reference's **default `update_window` of five**
and a five-pattern cycle, a kept promise stays alive for a whole cycle and is
then applied at the wrong phase - the prediction widens to forty nodes, two
thirds of the population. The pooled tests use a window of one for that reason.
Whether the reference intends that is not something this port can answer; its own
test leaves `DoPooling` commented out.

**Slice (d), inference backtracking, is in.** The last ten inputs are kept, and
when a step arrives mostly unpredicted - or leaves too little predicted - they
are re-played on the assumption that the sequence began further back than the
pooler thought: the first re-played input on its start cells, the rest as they
were. Starts are tried farthest back first and the first one that survives to
the input that arrived wins, because context is what a prediction is made of.
When none survives the step bursts exactly as it did before, which is what the
reference does when backtracking finds nothing.

The observable claim is the one the reference makes in prose: two sequences that
share a pattern, `0-1-2-3-4` and `2-8-9`, following the first and then reading
`8`, which the pooler did not predict. Without the re-play every node of `8`
bursts - twenty cells. With it the pooler works out that `8` continues a sequence
that began three steps ago and activates the ten cells that were predicted, and
so predicts `9` next.

Three things about the reference here. Its loop looks as if it compares the
confidence of one start against another and its comment describes that, but as
written it breaks after the first start that locks on, so **the farthest start
that survives wins** - that is what this port does, and it is what the comment's
own goal asks for. Its history buffer is popped from the wrong end when it is
full (a bug that would throw away the newest input); this port drops the oldest.
Its `inferPhase2` decides "enough predicted going forward" by counting *cells*
against half the average *column* density, which is kept as it is.

**Slice (e), the actor form, is in.** `TemporalPoolerActor` is one actor, not a
set of shards, and that is a finding rather than a shortcut: a temporal memory's
segment reaches cells of its own column, so its columns split cleanly between
shards, while a pooler's segment reaches across nodes and its prediction is
decided by scanning the whole population. There is no part of a pooler's state
that can be owned separately. So the actor is the ordering - steps answered in
the order they arrive - and the answer is a value, `ClaOutput`, so nothing that
crosses back points into the pooler. The test compares every answer with the
one-process pooler's, which is the rule this repository holds every actor form to.

**Slice (f), learning backtracking, is in.** The learning pass keeps its own
history of inputs, and when it would begin a sequence - the PAM counter has
expired, or the longest sequence worth naming has been reached - it first looks
for where the sequence these inputs are part of began, walks that path again
teaching it, and continues from there. Beginning on start cells throws away the
step before the seam, so a sequence learned in pieces never joins up; the re-play
is what joins them.

The measured claim, and the test that states it: a five-pattern cycle learned
with a length limit of four steps is the same cycle with either setting, but the
pass that may look back grows **60 segments instead of 100** - it re-enforces the
path it found rather than beginning a fresh one every four steps. Ten patterns
with a limit of eight: 130 against 150.

Two things about this one. The input that arrived *is* re-played - it is the one
that has to be explained - but a prediction for what follows it is the caller's
phase two, so the re-play stops after activating it; getting that wrong is worth
20 segments and a ruined transition, which is how it was found. And the re-play
that only asks "does the sequence hold" is read only: it activates the predicted
cells and nothing else, which is why it can be tried from every start in the
history before one is chosen.

**Slice (g), a forecast several steps ahead, is in.** `predict(steps)` answers the
confidence the pooler would put on every node at each of the next steps: the
first from the state it is in, and each one after that by taking what was
predicted as the next step's activity and reading what *that* predicts - the
reference's `Predict`, which is what a CLA has instead of replaying its whole
sequence memory. The state is put back before it answers, so asking what comes
next does not decide it, and the test states both halves: a learned cycle is
named three steps out, and the pooler is where it was afterwards.
`node_confidences()` is the same soft answer for the step it is on.

**That is the whole of the reference's pooler**, apart from what was left out on
purpose, and each of those is a decision rather than a gap:

- `topDownCompute` / `columnConfidences` - the confidence vector, which is here as
  `node_confidences` and, per step, inside a forecast.
- `outputType`, with `ActiveState` and `ActiveState1CellPerCol` - which cells a
  step *shows*. This port answers the reference's `Normal` (active or predicted),
  because the others are choices about what to display, and a display is not what
  a library hands to the next region.
- `updateAvgLearnedSeqLength`, `temporalPoolerPrint.go`, `temporalPoolerStats.go` -
  diagnostics for a printer and a chart. The measurements they exist for are in
  the tests and in this page, taken where they can be checked rather than printed.
- `GetSegId`, `removeSegmentUpdate`, `cleanUpdatesList` - bookkeeping the reference
  needs because it keeps its proposals in a map keyed by a segment id. Here the
  proposals are one array and expiry is a step count; the same decisions, without
  the ids.

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

### 2. Give the temporal region the two things the pooler already has — done

**Landed.** The region has a deadline (`TemporalRegion(params, shards, 250)`), a
one-retry policy for silent bands, `reconfigure`, and it says which bands it
missed in `TemporalOutput.missing`. The answer to "what should a region with a
missing band decide" is: the step it can compute, out loud - the cells that are
there are real, and a prediction without a band is a narrower prediction rather
than a wrong one.

Two things it taught, both worth knowing before touching it again. Each pass is
its own `TemporalBallot` actor, because an answer must belong to the pass that
asked for it, not to whichever pass happens to be open. And the region has to
**hold** that ballot: a pass waiting out a deadline is reachable only through its
own timer, so a ballot nobody holds is collected along with the timer of its
retry, and the round waits for an answer that can no longer come. A second timer
also needs a fresh `Timers` wheel - adding one to the wheel that is firing
silently drops it.

### 3. Multi-step prediction — done

`PredictionClassifier(memory, categories, learning_rate, steps)` keeps one
classifier per step and the last `steps` expectations: the classifier for step k
is taught by the expectation made k steps back and asked about the newest one.
`best_at(k)` and `probabilities_at(k)` answer k steps ahead, and asking beyond
what it was built for raises rather than answering zero, because a number nobody
computed would look like a prediction with no confidence behind it.

The test teaches a three-step cycle and reads steps one and two off the same
observation.

### 4. A combiner for two SDRs — done, before item 3

`SDRMerger` (`concat`, `subsample`) landed ahead of multi-step prediction: it is
additive, one new module with nothing existing touched, and the music work below
needs it sooner. `concat(left, right, shift)` puts a second space where the first
ends and merges positions that land on each other; `subsample(indices, most,
seed)` keeps at most that many, reproducibly.

The reference's third mode, distorting a representation, is deliberately not
here: nothing asks for it and the account of what it should do is unclear. Write
it when something needs to say what "distorted" means.

### 5. A fixed-width category encoder — done

`SDRCategoryEncoder` is in `htm/encoders/`: fixed `size`, `bits` random
positions per label (two percent of the width by default, `htm.core`'s density),
labels added as they are met, and an `unknown()` that exists before any label
does. `RandomPositions` is the draw, on a primitive because a constructor cannot
call its own methods - `this` is `tag` until every field is assigned, and the
unknown category is the last one.

It was written for a stream of labels whose number is not known; the closed-set
`CategoryEncoder` stays as it is, and the two encodings are deliberately not
comparable - they disagree about whether two labels may share a bit.

### 6. A graph as one SDR — done, as a design

`GraphEncoder` in `htm/encoders/` with `GraphEdge` beside it. Three decisions,
all written down where a reader meets them: a node is a category (open-set
encoder, so a node met anywhere keeps its bits); an edge is its two nodes with the
arriving one shifted past the node width, which makes direction part of the edge
rather than a flag beside it; a graph is the union of its edges' positions,
optionally cut to a cap.

The union is the decision worth arguing about - it loses multiplicity and lets a
dense region dominate - but keeping edges apart would be a set of
representations, which a pooler cannot consume.

Node bits are drawn at random, so two unrelated nodes may share one and unrelated
graphs overlap by a position or two. Sharing an edge is a much larger overlap,
and that is what the tests state. Grid cells and SimHash were once mistaken for
this; they are not it.

### 7. Smaller, already-diagnosed

- **Anomaly likelihood has no red/yellow filter.** Deliberate — it is a display decision —
  but a caller that wants one now has to write it.
- **Anomaly likelihood on a flat stream reads oddly — documented and pinned.** Both
  floors at work are now in [anomaly detection](anomaly-detection.md#the-likelihood)
  with the arithmetic (mean held at 0.03, variance at 0.0003, so a zero reads about
  0.958), and `test/anomaly_likelihood_test.pony` asserts that number so nobody
  changes it by accident. The floors stay: they are the reference's, and without them
  a near-zero stream would report the first hair's movement as a certainty.
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
- **A timer callback is reachable only through its own timer.** A ballot actor
  whose pass is waiting out a deadline is held by nothing else, so it is
  collected - together with the timer of its retry - and the round waits forever
  for an answer that can no longer come. The region holds the ballot in flight
  for exactly that reason.
- **A second `Timer` on the same `Timers` wheel, created from inside a timer
  callback, never fires.** Give each deadline a fresh `Timers` (as
  `TemporalBallot._watch` does) or route the retry through another actor, as
  `BallotBox` does by being created fresh for every round.
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
