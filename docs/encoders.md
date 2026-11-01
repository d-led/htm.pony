# Encoders

Two encoders are implemented: scalar and date. Both produce `Array[Bool]` and
both report failure as `EncodingFailed` rather than raising.

## Scalar encoder

`ScalarEncoder` sets a contiguous block of bits, and the block slides with the
value. The encoding is linear, so a nonlinear sense of distance has to be
applied to the value before it is encoded.

```pony
let params = ScalarEncoderParams(23, 0, 1 where radius' = 0.5, periodic' = true)
let encoder = ScalarEncoder(params)?

match encoder.encode(0.55, false)
| let bits: Array[Bool] => /* 46 bits, 23 of them set */
| EncodingFailed => /* not reached with these parameters */
end
```

### Parameters

| Field | Default | Meaning |
| --- | --- | --- |
| `width` | — | how many bits are set per value; must be odd |
| `min_val`, `max_val` | — | the range; `min_val` must be below `max_val` |
| `periodic` | `false` | whether the ends of the range are adjacent |
| `output_type` | `N` | which of `n`, `radius`, `resolution` was given |
| `n` | `0` | the number of bits in the output |
| `radius` | `0.0` | the range the set block covers |
| `resolution` | `0.0` | how much the value must change to move one bit |
| `range` | `0.0` | the extent to encode |
| `clip_input` | `false` | whether to clamp out-of-range values |
| `name` | `""` | used in error messages |
| `verbosity` | `0` | unused |

Exactly one of `n`, `radius` or `resolution` may be set. The others are derived:

- given `radius`, `resolution = radius / width`;
- given `resolution`, `radius = resolution * width`;
- given `n`, the resolution follows from the range and the width.

The constructor raises, rather than returning `EncodingFailed`, when the
parameters cannot describe an encoder at all: an even width, `min_val` at or
above `max_val`, more than one of the three sizes set, or none of them.

### A worked encoding

The [scalar encoder example](examples.md#a-scalar-encoder) uses width 23, range
0 to 1, radius 0.5, periodic. That gives a resolution of 0.5/23, about 0.0217,
and an output of 46 bits:

```
0.5    ............#######################...........
0.55   ..............#######################.........
0.6    ................#######################.......
0.65   ..................#######################.....

bits shared with the next value:
0.5    21
0.55   21
0.6    21
```

Each step of 0.05 is about 2.3 resolutions, so the block moves two bits and the
two values keep 21 of their 23 bits in common. A smaller step would move the
block less, and a step below one resolution would not move it at all.

### Decoding

`decode` maps an encoding back to the value range it covers. The top-down mapping
is kept in `top_down_mapping`, a `SparseBinaryMatrix` from bits to ranges. It is
unset until something asks for it.

### The width warning

The constructor warns when `width` is below 21:

```
WARNING: ScalarEncoder: Number of bits in the SDR must be greater than 21. Now: 5
```

The Go original warns here too and does not fail. A narrow encoding still works;
it just does not carry very much. The message goes to stdout through
`Debug.out`, so it appears among program output rather than on stderr.

## Date encoder

`DateEncoder` is meant to encode five fields of a timestamp into one vector, one
after another with fixed offsets:

| Field | Range | Width default | Radius default |
| --- | --- | --- | --- |
| season | days in the year, 0 to 366 | 3 | 91.5 |
| day of week | 0 to 7 | 1 | 1 |
| weekend | 0 to 1 | 3 | 1 |
| holiday | 0 to 1 | 0 | 1 |
| time of day | hours, 0 to 24 | 5 | 4 |

A width of 0 switches a field off and leaves a gap of no bits. Holidays come
from `holidays`, a list of `(month, day)` pairs, because a holiday that moves is
not expressible.

```pony
let params = DateEncoderParams(where
  season_width' = 3,
  day_of_week_width' = 1,
  weekend_width' = 3,
  time_of_day_width' = 5
)
let encoder = DateEncoder(params)?
```

`encode` takes a `PosixDate`:

```pony
let encoded = encoder.encode(PosixDate(1288882500, 0)) as Array[Bool]
```

### What it does not do yet

Only the season field is written. `encode` calls the season encoder and returns
the vector:

```pony
match season_encoder.encode_at_pos(_get_season_scalar(input), learn_unused, output, season_offset)
| EncodingFailed => EncodingFailed
else
  output
end
```

The day-of-week, weekend, holiday and time-of-day encoders are constructed, and
they contribute to `width`, but nothing calls them. Their bits stay `false`.

So the vector is correct in size and correct in its season bits, and the rest of
it is empty. `_get_holiday_scalar` is written but its body returns zero: the
computation for "the day before, the day of, and the day after" is present as
commented Go code.

The test for the date encoder asserts the `PosixDate` fields and logs the
encoding; the assertion that would compare the full vector is commented out.

## No-op encoder

`NoOpScalarEncoder` reports `noop()` as true, contributes no width, and returns
`EncodingFailed` from `encode` on purpose. It exists so a switched-off date field
can be held in the same field as a real encoder, and `encode_at_pos` is a no-op
so the date encoder can call it blindly.

Calling `encode` on it is a programming error, and the log line says so.

## Category encoder

`CategoryEncoder` is for labels that have no order between them. Each category
owns three consecutive positions of the output by default, and no two
categories share one:

```pony
let encoder = CategoryEncoder(recover val ["north"; "south"; "east"; "west"] end)?
let encoded = encoder.encode("east")   // bits 6, 7 and 8 of twelve
```

The output is `bits * categories` wide, so a population that grows with the
number of labels is the price of not knowing them in advance. Unlike the
[scalar encoder](#scalar-encoder), neighbouring categories do not slide into
each other: there is nothing between two categories for a slide to happen in,
and two different categories must have nothing in common.

An unknown category is `EncodingFailed`.

nupic's category encoder keeps its first block for `<UNKNOWN>` and encodes
anything it has not seen there. This one refuses instead - a stream where
unseen labels quietly become a real block is a stream whose labels stopped
being checked - and that is the only difference from the reference.

`decode` reads a category back by finding the busiest block, which is what
still works after a pooler has been at the representation.

## Not implemented

| Encoder | Would need |
| --- | --- |
| RDSE | a random distributed encoding for a range, as in `htm.core` |
| Graph | a decision first: no implementation in the reference repositories defines one |

## Image encoder

`ImageEncoder` turns a picture into a representation, so that two pictures of
something similar give overlapping ones. It is described on its own page in
[Picture encoders](image-encoder.md) and shown end to end in
[the example](examples.md#picture-similarity).

The part that is missing is reading a file — Pony has no image decoder — so it is
supplied by one FFI call to [stb_image](https://github.com/nothings/stb):
`StbDecoder` reads PNG, JPEG, BMP and GIF into a `GrayscaleImage`, and the rest
of the page above it stays unaware of file formats. See
[reading a file](image-encoder.md#reading-a-file).
