# Examples

Each subdirectory is a self-contained Pony program demonstrating a different
part of the library.

## [first-representation](first-representation/)

Encodes a value with `ScalarEncoder`, gives the encoding to a `SpatialPooler`,
and prints the columns that answer. Prints the same for three more values and
counts how many columns two neighbouring values share, which shows that nearby
values get nearby representations. Start here if you're new to the library.

## [in-process-pooler](in-process-pooler/)

Builds a pooler of 64 columns over a 64-bit input and prints what four columns
reach: their receptive field, and how many inputs they connect to. Feeds the
pooler one input, prints the representation, then builds a second pooler from the
same seed and compares the two answers. Demonstrates `Wiring.receptive_field`,
`SpatialPooler.compute` and the determinism that the seed provides.

## [pooler-learning](pooler-learning/)

Builds two poolers from the same seed, one that learns and one that does not, and
shows what sixty rounds do: a winning column's permanences move towards the
input, a column that keeps losing is boosted, and a column that never overlaps is
raised. Ends by checking that the pooler that only watched is unchanged.

## [pooler-training-value](pooler-training-value/)

Shows eight patterns to a pooler that learns and to one that only looks, over
five seeds, then damages each pattern - losing bits, and then gaining bits - and
prints how much of the clean representation each pooler still reaches. The two
tables are the answer to "what does learning buy?", and the per-seed rows under
them are the spread that makes the answer worth anything.

## [pooler-settings-value](pooler-settings-value/)

Measures what the CLA pooler's settings are worth on two streams: a cycle of ten
patterns, where pooling names the pattern after the next one too and costs three
times the segments, and two sequences that share a pattern, where the re-play
holds the state to ten cells instead of bursting eighty.

## [boosting-value](boosting-value/)

Two hundred columns over two hundred inputs, five of twenty bits, through two
poolers that differ in one setting: one may boost the columns it never hears by
up to tenfold, the other may not boost at all. Nothing else can move - the
learning rate is zero - so the count of columns that have never won is decided
by boosting alone. Prints that count at three checkpoints over five seeds.

## [sequence-training-value](sequence-training-value/)

Runs one cycle of four symbols through two watchers - a memory over a pooler that
learned the symbols, and a memory over a pooler that only looked - then knocks a
bit out of every symbol and scores the sequence again. Prints the anomaly score
for the clean cycle and for one and two bits of damage, over five seeds.

## [actor-pooler](actor-pooler/)

Wires 64 columns into four `ColumnShard` actors, hands them to a `Pooler`, and
runs sixty learning rounds on it and on an in-process `SpatialPooler`. The asking
side is an actor that implements `Representation`, compares every answer with the
in-process one, and asks for the next round. Demonstrates the message path —
`Pooler.represent`, `Ballot.cast`, `Representation.represented`,
`ColumnShard.learn` — and that grouping columns into shards does not change what
the pooler computes or learns.

## [scalar-encoder](scalar-encoder/)

Encodes four values with a scalar encoder and prints each encoded bit vector,
with `#` for a set bit. Counts the bits each pair of neighbours shares.
Demonstrates `ScalarEncoderParams` and `ScalarEncoder.encode`, and the sliding
block of set bits that makes similar values share most of their encoding.

## [image-similarity](image-similarity/)

Encodes a picture, the same picture twice as wide, a brighter copy of it, and a
different picture, then reports the fingerprint distance and how many columns of
the spatial pooler each one shares with the first. Demonstrates `DifferenceHash`,
`ImageFingerprint` and `ImageEncoder`, and that scale and brightness leave a
picture's representation unchanged while an unrelated picture shares few columns.

## [temporal-memory](temporal-memory/)

Teaches a temporal memory that one column follows another, then shows the first
column alone and reads what the memory expects next. Then shows the second,
which no longer bursts because it was predicted. Demonstrates `TemporalMemory`,
`TemporalMemoryParams` and `TemporalOutput`.

## [temporal-memory-on-actors](temporal-memory-on-actors/)

Runs a sequence of two columns through the in-process memory and then through a
`TemporalRegion` of two shards, comparing the two step by step. A step is two
passes over the shards - activate, then predict - because a prediction is about a
state that includes what every column did.

## [temporal-pooler](temporal-pooler/)

Teaches a `TemporalPooler` five patterns in order, ten times, then shows the
first alone and asks what follows. Prints the nodes it predicts, then a forecast
three steps out - the third step read from a state that follows from the first
two rather than from input - and shows that asking left the pooler where it was.

## [temporal-pooler-recovery](temporal-pooler-recovery/)

Teaches two sequences that share a pattern, follows one of them into an input
only the other contains, and prints the active cells: ten, one a node, rather
than the twenty a burst would turn on. That is the pooler re-playing the recent
inputs and finding the earlier start instead of giving up on the sequence.

## [anomaly-stream](anomaly-stream/)

Streams three repeating inputs followed by one that breaks the pattern, printing
the anomaly score and a bar for each step. Shows the score falling to zero as the
pattern is learned and jumping when it is broken. Demonstrates
`StreamingAnomalyDetector` and `TemporalOutput.anomaly()`.

## [anomaly-likelihood](anomaly-likelihood/)

Two hundred steps of ordinary anomaly scores, then one that is not, put through
`StreamingAnomalyDetector`'s likelihood estimator. Shows a raw score read
against the steps before it, which is what turns a number into a probability.

## [prediction-baselines](prediction-baselines/)

Asks a temporal memory, and three guesses that need no learning, which of each
step's columns they expect: the last input, the most common columns, and
everything. Runs it twice - over six symbols in a fixed order, where only a
memory can follow, and over a value that climbs and falls, where repeating the
last input is hard to beat. Prints what share of each step's columns each method
missed, and how often it was exactly right. Every other example here compares
the library with itself; this one compares it with not learning at all.

## Running them

Build and run one from its own directory:

```
cd first-representation
corral run -- ponyc --debug
./first-representation
```

`run-all.sh` builds and runs every example in the order above.
