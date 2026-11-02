# Roadmap

What this project is for, in the order the goals were set, and what is left.

## The goal

A complete **actor-native HTM/CLA in Pony**, end to end, aligned with the HTM and
NuPIC implementations it is ported from: the [Go reference](https://github.com/htm-community/htm)
first, with `htm.java`, `htm.core` and the NuPIC line beside it where they say
something the Go one does not.

The three things the library is meant to do, in the order they were asked for:

1. **predictions** - what tends to follow what, from cells that predict;
2. **classification** - a label or a value for that prediction;
3. **online streaming anomaly detection** - how surprising the next step is,
   learned as the stream arrives.

Everything in the pipeline runs twice: once in process, and once as actors
pushing messages, with tests that fail when the two disagree.

## Where that stands

| | state |
| --- | --- |
| Spatial pooler | done, in process and on actors |
| Permanence learning, duty cycles, boosting | done, in process and on actors |
| Temporal memory: cells, segments, prediction, bursts | done, in process and on actors |
| Predictions | done - cells predicting the next step |
| Classification | done - SDR classifier and prediction classifier |
| Streaming anomaly score and its likelihood | done, in process |
| Anomaly detection joined to the actor pipeline | done - `AnomalyStream` joins the pooler and the region |
| **CLA temporal pooler** | **in slices** - a step with and without pooling, and inference backtracking, verified against the reference's own sequence test; learning backtracking and the actor form are not in |
| A graph as one SDR | done - a node is a category, an edge is two nodes and a direction, a graph is the union |
| Grid cell encoder | done - a place becomes periodic receptive fields |
| SimHash document encoder | done - a document becomes the positions its words vote for |
| Date encoder | done - season, day of week, weekend, time of day, holidays |

## What is next, in order

**1. The CLA temporal pooler.** This is the piece the port was aimed at and the
last one missing from the algorithm: the Go `temporalPooler.go` it comes from is
about two thousand lines, and it is what turns a stream of predictions into
stable, hierarchically pooled representations rather than a burst per step.
Nothing else in the plan moves forward much until it is there.

**2. Anomaly detection on the actor path.** Done: `AnomalyStream` asks the pooler
for columns, hands them to the temporal region, and scores what comes back, one
step in flight at a time so that a score is always a statement about the step
before it. The test holds it to the claim the repository exists for - the same
steps scored on actors give the scores they give in one process. The region has
since gained what the pooler had learned first: a deadline, one retry for the
bands that stayed silent, `reconfigure`, and an answer that names what it missed;
see [actors](actors.md).

**3. The date encoder, upgraded.** Done: the encoder writes day of week, weekend,
time of day and holidays beside the season, against the reference's own expected
bits. Writing it turned up a bug worth remembering - `ScalarEncoder.encode_at_pos`
ignored its offset, so every field of a date was written at the start of the
vector and the test that should have caught it asserted nothing.

**4. The category encoder, checked against the modern one.** Checked, and the
answer is that they are different shapes rather than one being right. Ours gives
each label its own contiguous block, so the width grows with the labels and two
labels share nothing. `SDRCategoryEncoder`, in `htm.java` and in `nupic`, holds a
fixed width `n` and turns on `w` random bits per label, so labels may share a few
bits, the width stays put, and a label that arrives later is added as it is met.
Both are in the references, neither is wrong, and the encoder says which one it
is. The fixed-width one is not written here; it is the shape a stream of labels
of unknown number wants, so it is the natural next addition if a stream needs it.

**5. The graph encoder.** None exists in the Go reference - that was checked - so
this is new work rather than a port. Two encoders are wanted:
`GridCellEncoder`, location as periodic receptive fields, and
`SimHashDocumentEncoder` for sets of ids, rather than inventing a third scheme.

Grid cells are done. The implementation follows `GridCellEncoder` in `htm.core`,
which is AGPL and is therefore written from its account of the algorithm rather
than transcribed: the cells that fire for a seed are not that library's cells, and
the test of the golden bits it ships is deliberately not ported, because it pins
which numbers a numpy random stream produces rather than anything about the
encoding. What is held to the same standard is the relation the algorithm exists
for: a one-unit move keeps about three quarters of the cells, and beyond the
shortest period fewer than two fifths.

SimHash over documents is done too, on the same terms: the words of a document are
digested, each digest votes over every position, and the highest totals are set.
The digest is this library's rather than that library's, so the bits are not
theirs either, and the tests hold the property instead - documents sharing words
overlap, a different sentence shares nothing, the same document always encodes
the same way.

What is still not written is a graph encoder in the literal sense: a graph - nodes
and the edges between them - encoded as one SDR. Neither of the two above does
that, and none of the reference implementations has one.

## The picture side is an experiment, not the point

The image encoder exists because a resolution-independent similarity hash is a
good way to see whether the pipeline handles a representation that arrives as
pixels. It is deliberately *not* on the main line: the decision recorded when it
was written was to keep it off master until the pooler consumes an SDR end to end,
then build a corpus of real, noisy pictures, measure how far the Hamming distance
drifts under the distortions that matter, and only then choose the hash.

The next thing worth doing there is an **example rather than a library feature**:
run common datasets through it - the ones deep learning is known to struggle with,
rotations, texture against shape, noisy handwriting - and show what a spatial
pooler and a temporal memory make of them. That is a demonstration of the
representation, not a claim that this library classifies pictures.
