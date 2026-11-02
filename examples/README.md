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

Shows eight patterns to a pooler that learns and to one that only looks, then
damages each pattern - losing bits, and then gaining bits - and prints how much
of the clean representation each pooler still reaches. The two tables are the
answer to "what does learning buy?", and the prose under them says which side
of the comparison each kind of damage lands on.

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

## [anomaly-stream](anomaly-stream/)

Streams three repeating inputs followed by one that breaks the pattern, printing
the anomaly score and a bar for each step. Shows the score falling to zero as the
pattern is learned and jumping when it is broken. Demonstrates
`StreamingAnomalyDetector` and `TemporalOutput.anomaly()`.

## [anomaly-likelihood](anomaly-likelihood/)

Two hundred steps of ordinary anomaly scores, then one that is not, put through
`StreamingAnomalyDetector`'s likelihood estimator. Shows a raw score read
against the steps before it, which is what turns a number into a probability.

## Running them

Build and run one from its own directory:

```
cd first-representation
corral run -- ponyc --debug
./first-representation
```

`run-all.sh` builds and runs every example in the order above.
