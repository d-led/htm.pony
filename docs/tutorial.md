# Tutorial: one number in, a set of columns out

This walks through `examples/first-representation`, which is a complete program
of about ninety lines. Everything it prints below is real output.

```
cd examples/first-representation
corral run -- ponyc --debug
./first-representation
```

## Step 1: turn a number into bits

An encoder produces the bit vector the pooler takes. This one encodes a value
between 0 and 1 with 23 bits set out of 46:

```pony
let params = ScalarEncoderParams(23, 0, 1 where radius' = 0.5, periodic' = true)
let encoder = ScalarEncoder(params)?
```

`encode` returns either the vector or `EncodingFailed`, so the caller matches on
the result rather than wrapping the call in a `try`:

```pony
match encoder.encode(value, false)
| let bits: Array[Bool] => bits
| EncodingFailed => /* the parameters were wrong */
end
```

The width comes from the encoder, not from the caller. `encoder.n` is the number
of bits:

```
encoder output: 46 bits
```

That number is needed in the next step.

## Step 2: build a pooler over that width

The pooler's input has to be exactly as wide as the encoder's output. A mismatch
is not a bug the pooler can work around, so it is a configuration error:

```pony
let config = SpatialPoolerConfig([8; 8], [46], true, 2.0)
let pooler = SpatialPooler(config, 42)?
```

That reads as: an 8 by 8 grid of columns, an input of 46 bits, global
inhibition, two active columns per inhibition area.

The last number becomes a fraction. An inhibition area of radius 1 covers 9
cells, so two of them is 2/9, about 0.222, and that fraction of 64 columns
is what may be active at once:

```
columns: 64, active per round: 14
```

The seed decides how the columns are wired. The same seed always wires the same
pooler.

## Step 3: compute a representation

The example wraps that match in a helper, `_encode`, and hands the result to the
pooler:

```pony
let representation = pooler.compute(_encode(encoder, 0.50)?)?
```

The result is the list of columns that recognise the input:

```
0.5   14 17 27 28 30 31 34 35 37 38 39 41 44 49
```

Fourteen columns out of sixty-four. Those are column indexes, not input bit
positions.

## Step 4: move the value a little

```
0.5   14 17 27 28 30 31 34 35 37 38 39 41 44 49
0.55  14 27 28 30 31 34 35 37 39 41 43 44 48 52
0.6   28 30 31 33 34 35 36 37 39 41 43 44 52 56
0.9   11 20 24 31 36 40 41 42 48 52 56 57 61 62
```

Two neighbouring values share eleven of their fourteen columns. The pair at
0.6 and 0.9, further apart, shares five:

```
0.5 and 0.55  11
0.55 and 0.6   11
0.6 and 0.9    5
```

This is the property the whole pipeline is built for. The encoder turned 0.5 and
0.55 into vectors that share most of their bits; the pooler turned those vectors
into representations that share most of their columns. The two values are
recognised as similar without anything comparing the numbers. Move the values
further apart and fewer columns are shared.

## Step 5: the same thing on actors

Nothing above needed an actor. When you want the columns spread across cores,
the same computation is available as messages: shards of columns push their
overlaps into a ballot box, and a pooler coordinator inhibits the tally and
pushes the answer back.

[The actor example](examples.md#the-same-computation-on-actors) does exactly
that and checks the answer against the in-process one.

## Things to try

**Change the seed.** `SpatialPooler(config, 42)?` — try 7. Different columns get
wired to different inputs, so a different set of columns answers. Nothing is
better or worse; they are different populations.

**Switch to local inhibition.** Pass `false` as the third argument. Columns then
compete only with their neighbours, and two distant regions of the grid can each
put a column forward. The representation changes, the pipeline does not.

**Give it a width it does not expect.** Pass a 45-bit vector to `compute` and
watch it raise. That is deliberate: a short input would leave columns reading
past the end of it.

**Encode something else.** The pooler does not care where the bits came from.
Any `Array[Bool]` of the right width is an input.
