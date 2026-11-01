# Sparsity

A sparse representation has many positions and few of them set. The pooler in
this repository produces one: 64 columns, of which a dozen or so are active.

Sparsity is not a side effect. It is what makes the representations comparable by
counting shared positions, and what lets many different inputs share one
population of columns without colliding.

## Where sparsity comes from

The encoder output is **not** sparse. The scalar encoder in
[the examples](../examples.md#a-scalar-encoder) sets 23 of 46 bits, half of them. It
encodes a value faithfully; it does not try to be economical.

Sparsity appears at the inhibition stage. [The tutorial](../tutorial.md) sets the
density to 2/9 and gets 14 active columns out of 64:

```
columns: 64, active per round: 14
0.5   14 17 27 28 30 31 34 35 37 38 39 41 44 49
```

The [in-process example](../examples.md#the-spatial-pooler-in-one-process) is sparser
still, because its input carries six set bits rather than a whole block:

```
active input bits: 3, 5, 8, 13, 21, 44
representation:    3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56
```

So the pipeline compresses on the way through. A dense encoding of one value
becomes a sparse set of columns, and the density setting decides how sparse.

## What the sparsity buys

Two representations of similar inputs share most of their active positions. Two
representations of dissimilar inputs share few. From the tutorial:

```
0.5 and 0.55  11
0.55 and 0.6   11
0.6 and 0.9    5
```

That is the whole comparison mechanism: count the shared columns. There is no
distance function and no arithmetic on the values. Neighbouring values share 11
of 14 columns; values a third of the range apart share 5.

A dense representation would not support this. If half the positions were set,
any two representations would share a large number of bits by coincidence, and
the count would say little about similarity.

## Distributed

Each active column is one weak piece of evidence, and the set is the claim. A
column does not carry "the value is 0.55"; it carries "some part of what I am
wired to matched". A dozen such columns together identify the input well enough
to be distinguished from others.

This is also why a missing or spurious column does not destroy the
representation. The remaining columns still point at the same input.

## What this repository does not measure

There is no test for noise tolerance, no capacity calculation, and no experiment
showing how many distinct inputs a population of this size can hold before two
of them collide. The sentences above are about the mechanism; the numbers are
the ones the examples print.

Sparsity is also not a setting of its own. It comes from the inhibition density,
described in [the spatial pooler guide](../spatial-pooler.md#density).
