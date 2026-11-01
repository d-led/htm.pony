# Examples

Ten programs live under `examples/`, each its own package with its own
`main.pony`. They print what they do and exit non-zero when a claim in them
fails.

```
./examples/run-all.sh
```

Each one can also be run alone:

```
cd examples/in-process-pooler
corral run -- ponyc --debug
./in-process-pooler
```

## The first representation

`examples/first-representation/main.pony` encodes four values with a scalar
encoder, gives each encoding to a pooler, and counts how many columns two values
share. [The tutorial](tutorial.md) walks through it line by line.

```
encoder output: 46 bits
columns: 64, active per round: 14

0.5   14 17 27 28 30 31 34 35 37 38 39 41 44 49
0.55  14 27 28 30 31 34 35 37 39 41 43 44 48 52
0.6   28 30 31 33 34 35 36 37 39 41 43 44 52 56
0.9   11 20 24 31 36 40 41 42 48 52 56 57 61 62

columns two values share:
0.5 and 0.55  11
0.55 and 0.6   11
0.6 and 0.9    5
```

Neighbouring values share eleven of fourteen columns; the pair at 0.6 and 0.9
shares five.

## The spatial pooler in one process

`examples/in-process-pooler/main.pony` builds a pooler of 64 columns over a
64-bit input, prints what four columns reach, feeds it one input, and reads back
the representation. It finishes by building a second pooler from the same seed
and comparing the two answers.

```
columns 64, inputs 64
density at radius 1: 0.222222

column   field      synapses
0       0..16      9
9       0..25      13
31      15..47     17
63      47..63     9

active input bits: 3, 5, 8, 13, 21, 44
representation:    3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56

a second pooler with the same seed gives the same representation
```

Read the table downwards. A column in the middle of the grid (31) reaches 33
inputs and connects to 17 of them; a column at an end (0, 63) reaches 17 and
connects to 9, because its field is clipped by the edge of the input.

Six active input bits produce twelve active columns. The columns are not the
input positions: column 3 is active because the column wired around input 3
happens to connect to several of the active bits, not because input 3 is on.

The code for the round trip:

```pony
let config = SpatialPoolerConfig([8; 8], [64], false, 2.0)
let pooler = SpatialPooler(config, 42)?
let representation = pooler.compute(input)?
```

`compute` raises when the input is not as wide as `config.num_inputs()`. An
input that no column matches is not an error; it gives an empty representation.

`compute(input, true)` learns from the round. The next example shows what that
does.

## What learning changes

`examples/pooler-learning/main.pony` builds two poolers from the same seed, one
that learns and one that only watches, and feeds both the same pattern for sixty
rounds.

```
the pattern is represented by columns 0, 4, 10, 20, 34, 44, 54

column 0 before learning:
  input 3  on   permanence 0.12
  input 12 off  permanence 0.12
  input 14 on   permanence 0.12
  input 8  off  permanence 0.06
  input 9  on   permanence 0.12
  input 1  off  permanence 0.11

column 0 after learning:
  input 3  on   permanence 1
  input 14 on   permanence 1
  input 9  on   permanence 1
3 of 9 connections grew towards the input

8 columns are being helped towards winning
  column 1   boost 10
  column 8   boost 10
  ...

the pooler that only watched is unchanged: inferences do not learn
```

Read the two column listings together. Before learning, column 0 believes in
three inputs that were on and three that were off, all at about the connection
threshold. After sixty rounds, the three that were on are at a permanence of one
and the three that were off have been let go of: their permanences fell below
half a learning step and were trimmed to nothing. The column has decided what it
is looking for.

Eight of the sixty-four columns are at the maximum boost, which means they never
won and are being pushed harder so that they can. That is the mechanism that
stops the population collapsing onto whichever columns happened to win first.

The pooler that only watched is bit for bit unchanged, which is the property the
last section checks: an inference does not learn.

## The same computation on actors

`examples/actor-pooler/main.pony` wires the same 64 columns into four shards of
sixteen, hands them to a `Pooler`, and asks for a representation. It also builds
the in-process pooler from the same seed, and compares the two answers when the
message arrives.

```
in process: [3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56]
on actors:  [3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56]
both paths give the same representation
```

The asking side is an actor that implements `Representation`:

```pony
actor Listener is Representation
  be represented(active: Array[USize] iso) =>
    /* the answer */
```

and the request is a message with no return value:

```pony
pooler.represent(input, Listener(this))
```

The example wires its shards with `Wiring.synapses` and one seeded generator,
which is how `SpatialPooler` wires itself. That is why the two lists match: the
actor layer moves where the work runs, and does not change what it computes.

Each shard's synapses are frozen into a value first, because a shard shares them
between actor messages:

```pony
let wired = Wiring.synapses(config, inputs, random, column)?
views.push(ColumnView(column, _frozen_synapses(wired)))
```

## The temporal memory on actors

`examples/temporal-memory-on-actors/main.pony` runs a sequence of two columns
through the in-process memory, then through a region of two shards, and compares
every step.

```
  active 0 1 2 3        expects -              bursts 0
  active 4 5 6 7        expects -              bursts 1
  active 0 1 2 3        expects 4              bursts 0
  active 4              expects 0              bursts -
  active 0              expects 4              bursts -
  active 4              expects 0              bursts -

the same sequence on two shards of two columns
  step 0 agrees
  ...
every step on actors matches the one in process
```

The first two steps burst: nothing has been learned yet, so every cell in the
column fires. By the third step column 0 expects column 1, and after that the
memory alternates between them, activating one cell of a column instead of all
four.

A step is two passes over the shards - activate, then predict - because a
prediction is about a state that includes what every column did. [Actors
explains](actors.md#the-temporal-memory-on-actors) why the second pass cannot
be folded into the first.

## Picture similarity

`examples/image-similarity/main.pony` encodes four pictures, fingerprints them,
and puts each representation through the spatial pooler.
[Picture encoders](image-encoder.md) explains what the two steps do.

```
picture           bits set  distance  columns  shared with the original
the original      10        0         18       18
twice the size    10        0         18       18
brighter          10        0         18       18
a different one   16        22        23       9
```

The pictures are built in code rather than read from a file, because reading a
file needs a decoder and Pony has none yet.

## Anomaly detection

`examples/anomaly-stream/main.pony` streams three repeating inputs and then one
that breaks the pattern, printing the anomaly score for each step.

```
a  ####################  1
b  ####################  1
c  ####################  1
a  ####################  1
b  ....................  0
...
a  ....................  0
b  ....................  0
c  ....................  0

d  ####################  1
```

The first four steps score one because nothing has been learned yet.
[Streaming anomaly detection](anomaly-detection.md) explains the reading.

## What a score is worth

`examples/anomaly-likelihood/main.pony` has no HTM in it at all: it feeds two
hundred made-up scores that wobble around 0.15, then one of 0.9, and prints what
each score is worth against the ones before it.

```
its idea of ordinary: centred at 0.151, spreading 0.017

step                    score   likelihood
an ordinary step       0.141   0.57
another ordinary step  0.183   0.517
the odd step           0.9     1

the noisiest ordinary likelihood in two hundred steps was 0.908
only the odd step comes near certainty
```

The score itself says nothing: 0.141 and 0.183 are both ordinary, and both read
above a half, because the value is one minus a tail probability and half of all
ordinary steps are above a half. What the odd step has that they do not is
distance from everything the estimator has seen.

[Streaming anomaly detection](anomaly-detection.md#the-likelihood) explains the
statistic, including the degenerate case of a stream that never varies.

## Prediction

`examples/temporal-memory/main.pony` teaches a temporal memory that one column
follows another, then shows the first alone and reads what the memory expects.

```
showing column 0 alone
  active cells:      [0]
  bursts:            [] (columns)
  predicts columns:  [1]

showing column 1, which was predicted
  active cells:      [4]
  bursts:            [] (columns)
```

A predicted column activates only the cells that were predicted, so it no
longer bursts. [The temporal memory](concepts/temporal-memory.md) explains why.

## A scalar encoder

`examples/scalar-encoder/main.pony` encodes four values and counts the bits each
pair of neighbours shares.

```
values 0 to 1, 46 bits, 23 set per value

0.5    ............#######################...........
0.55   ..............#######################.........
0.6    ................#######################.......
0.65   ..................#######################.....

bits shared with the next value:
0.5    21
0.55   21
0.6    21
```

Each step of 0.05 is about 2.3 resolutions, so the block of set bits moves two
positions and neighbours keep 21 of 23 bits. Move further and fewer bits are
shared; that is what lets the spatial pooler treat a near value as a near
representation.
