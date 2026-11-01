# Encoding

An encoder turns a value into a bit vector the spatial pooler can take. The
form matters more than the exact numbers: values that are close together should
produce vectors that share most of their set bits, and values far apart should
share few.

That property, not the arithmetic, is what makes the pooler able to generalise
from one input to a similar one.

## The interface

Every scalar encoder implements `SomeScalarEncoder`:

```pony
interface SomeScalarEncoder
  fun noop(): Bool
  fun encode(input: F64, learn_unused: Bool): (Array[Bool] | EncodingFailed)
  fun encode_at_pos(
    input: F64,
    learn_unused: Bool,
    output: Array[Bool] ref,
    pos: USize): (None | EncodingFailed)
```

`encode` returns a new vector. `encode_at_pos` writes into a vector at an
offset, which is how the date encoder assembles one vector out of five.

Failure is a value, `EncodingFailed`, not an exception. A caller that has a
fallback can match on it without a `try` around the call.

`learn_unused` is part of the signature for parity with the Go original. No
encoder in this repository reads it; both ignore it.

`noop()` reports whether the encoder writes anything. `NoOpScalarEncoder`
reserves width and writes nothing, so a date field that is switched off leaves a
gap of the right size and the offsets of the fields after it stay correct.

## Shared bits, not shared values

The scalar encoder sets a contiguous block of bits; the block slides as the
value rises. Since neighbouring values place overlapping blocks, they share
bits. Below a step of one resolution the block does not move at all, so two
distinct values can produce the same vector.

[Examples](../examples.md#a-scalar-encoder) prints this for four values, with
the shared-bit count beside each.

## What to encode with

| You have | Use |
| --- | --- |
| A number in a known range | `ScalarEncoder` |
| A timestamp | `DateEncoder` |
| A category, an image, a set of ids, a graph | Nothing yet |

The category encoder, the random distributed scalar encoder, and the image and
graph encoders are not written. [Encoders](../encoders.md) says what each
missing one would need.
