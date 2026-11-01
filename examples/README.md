# Examples

Each subdirectory is a self-contained Pony program demonstrating a different
part of the library. Ordered from simplest to most involved: the first two build
a representation, the third builds the same one out of actors, and the last
covers encoding on its own.

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

## [actor-pooler](actor-pooler/)

Wires the same 64 columns into four `ColumnShard` actors, hands them to a
`Pooler`, and asks for a representation. The asking side is an actor that
implements `Representation` and compares the answer with the in-process one.
Demonstrates the message path — `Pooler.represent`, `Ballot.cast`,
`Representation.represented` — and that grouping columns into shards does not
change the result.

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

## [anomaly-stream](anomaly-stream/)

Streams three repeating inputs followed by one that breaks the pattern, printing
the anomaly score and a bar for each step. Shows the score falling to zero as the
pattern is learned and jumping when it is broken. Demonstrates
`StreamingAnomalyDetector` and `TemporalOutput.anomaly()`.

## Running them

Build and run one from its own directory:

```
cd first-representation
corral run -- ponyc --debug
./first-representation
```

`run-all.sh` builds and runs every example in the order above.
