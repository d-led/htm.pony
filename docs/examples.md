# Examples

Four programs live under `examples/`, each its own package with its own
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

The table is worth reading downwards. A column in the middle of the grid (31)
reaches 33 inputs and connects to 17 of them; a column at an end (0, 63) reaches
17 and connects to 9, because its field is clipped by the edge of the input.

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
