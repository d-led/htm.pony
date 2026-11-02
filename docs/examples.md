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

## What learning is worth

`examples/pooler-training-value/main.pony` asks whether learning changes what a
pooler does with a pattern once that pattern is damaged. It shows eight patterns
to a pooler that learns and to one that only looks, over five seeds, then damages
each pattern two ways and compares each pooler's answer with what the same pooler
said about the clean pattern.

One seed in full, so the shape of the damage is visible:

```
seed 3, in full
bits off    learning  looking
0           1.000     1.000
1           0.960     0.916
2           0.934     0.851
3           0.819     0.717

bits on     learning  looking
0           1.000     1.000
1           0.981     0.897
2           0.943     0.843
3           0.932     0.825
```

and then what learning was worth on every seed, averaged over one, two and three
damaged bits:

```
seed        bits off  bits on
3           +0.076    +0.097
5           +0.034    +0.080
11          +0.106    +0.007
23          +0.032    -0.016
41          +0.118    +0.048
mean        +0.073    +0.043

learning kept more of the answer on 5 of 5 seeds when a pattern lost bits,
and on 4 of 5 when it gained bits it never had.
```

A number is the share of the clean answer that still comes back. Learning pays
both ways, and pays most when the pattern loses bits: a column that learned is
connected to the bits the pattern uses, so losing one costs it one connection out
of eight, while a column that only looked had spread its connections over inputs
the pattern never turns on.

Five seeds rather than one, because the gain moves by a factor of two between
seeds and changes sign on one kind of damage. A single run of this study gave
"learning makes no difference when a pattern gains bits"; four more seeds said
otherwise. The last line of the seed table is the one to read; the rows under it
are the spread that makes the mean worth anything.

## What boosting is worth

A column that never wins never shows what it would have recognised, and a column
that cannot be heard cannot learn. `examples/boosting-value/main.pony` asks what
the boost is worth: two hundred columns competing for twenty places over five
inputs of twenty bits, run twice - once by a pooler that may boost the columns it
does not hear by up to tenfold, once by a pooler that may not boost at all.

The learning rate is zero in both runs, so no permanence is ever moved by a
winner and the only thing that can change who wins is a boost. That makes the
count of columns that have never won a measurement of boosting and of nothing
else:

```
        boosting                    no boost
seed    @50      @100     @200      @50      @100     @200
3       120      0        0         120      120      120
5       122      0        0         122      122      122
11      116      0        0         116      116      116
23      116      0        0         116      116      116
41      121      0        0         121      121      121
```

A checkpoint is a count of the inputs a pooler has seen. The pooler works out
what counts as normal activity every fifty inputs, so the checkpoint at fifty is
taken before any of that has been applied - and there the two columns are
identical, which is the control: the two poolers are the same pooler until a
boost exists to apply.

Fifty inputs later boosting has heard every column, on all five seeds. Without it
the count cannot move at all: about 120 of the 200 columns never win, and since
nothing else changes a winner in this setup, they never will.

The reference tests this as a property - that every column should win at some
point - and it is stated here as a measurement instead, because how many columns
go unheard depends on the wiring a seed happens to draw.

## What a learned pooler gives the memory

`examples/sequence-training-value/main.pony` asks the question the pattern study
leaves open: does a pooler that learned the symbols make a *sequence* of them
easier to follow?

It warms one pooler on a cycle of four symbols, leaves a second pooler wired as it
was built, then lets a temporal memory learn the same cycle over each. The pooler
is settled before the memory starts, so the comparison is about what the pooler
ended up believing rather than about a representation that was still moving. Then
it knocks bits out of every symbol and scores the sequence again:

```
seed    clean: L  W         1 bit: L  W         2 bits: L  W
3       0.000     0.019     0.033     0.142     0.072      0.245
5       0.221     0.000     0.517     0.269     0.555      0.307
11      0.000     0.000     0.064     0.105     0.146      0.178
23      0.000     0.000     0.021     0.019     0.380      0.269
41      0.000     0.000     0.019     0.227     0.096      0.236
mean    0.044     0.004     0.131     0.153     0.250      0.247
```

`L` is the watcher whose pooler learned, `W` the one whose pooler only looked, and
a number is the mean anomaly score - the share of a step's columns the memory did
not expect, so lower means the sequence was followed.

Most seeds learn the cycle to nothing on both sides. Seed 5 does not: its learned
watcher scores 0.221 on the clean cycle while the wired one scores nothing, which
is the one result here large enough to stand out from the spread.

What is left is not a difference between the two watchers. At one bit of damage
the learned pooler averages 0.131 against 0.153 and is better on three of five
seeds; at two bits 0.250 against 0.247, which is nothing. This study used to show
a clearer benefit - 0.051 against 0.189 at one bit - and that result came from a
pooler whose ties were broken by column index: with a frozen pooler the same
low-numbered columns keep winning, which is a stable representation for a memory
to learn and not a property of learning. Give ties to a nudge instead and the
advantage disappears into the spread.

The lesson is about the study, not the code: a comparison that rests on one
mechanism being switched off is worth re-running when the mechanism next to it
changes.

## The same computation on actors

`examples/actor-pooler/main.pony` wires 64 columns into four shards of sixteen,
hands them to a `Pooler`, and runs sixty learning rounds through it. It runs the
same sixty rounds through an in-process `SpatialPooler` built from the same seed
and compares the two answers round by round.

```
round 1 in process: [3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56]
round 1 on actors:  [3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56]
round 60 in process: [7, 8, 9, 19, 20, 21, 42, 45, 52, 55, 56]
round 60 on actors:  [7, 8, 9, 19, 20, 21, 42, 45, 52, 55, 56]
the two paths agreed on all 60 learning rounds
```

The representation moves between the first round and the sixtieth because those
rounds learn: the columns that keep losing are helped until they win, and the
winners have moved their permanences towards the input. That both paths move the
same way is the claim - the actor layer changes where the work runs, not what it
computes.

The asking side is an actor that implements `Representation`, compares the answer
with what one process gave for the same round, and asks for the next round:

```pony
actor Listener is Representation
  be represented(active: Array[USize] iso) =>
    /* compare the answer, then ask again */
```

and the request is a message with no return value:

```pony
pooler.represent(input, true, Listener(this, pooler, input))
```

`PoolerShards.build(config, seed, width)` cuts the population into bands and wires
each column as `SpatialPooler` wires its own: in column order, from one seeded
generator, raised until it can be heard and trimmed. Both paths start from the
same population, which is what makes the answers comparable at all.

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

The pictures are built in code rather than read from a file, because the example
is about the encoder rather than the file format. `StbDecoder` covers PNG, JPEG,
BMP and GIF when a picture comes from a file.

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
