# Picture encoders

`ImageEncoder` turns a picture into a representation that overlaps with the
representations of similar pictures. Two pictures of the same thing at different
sizes, or at different brightnesses, give the same representation; two
unrelated pictures give representations that share little.

It takes two steps, and the second one is the interesting part.

## Step 1: a fingerprint

`DifferenceHash` reduces a picture to 9 by 8 brightness values by averaging
every source cell, then reads each row left to right, setting a bit where a cell
is brighter than the one after it. Eight rows of eight comparisons make 64 bits.

The reduction to 9 by 8 is what makes the fingerprint independent of size. A
200 by 200 picture and a 2000 by 2000 picture of the same scene average to nearly
the same grid and give the same bits. Averaging, rather than sampling, is what
stops grain and a one-pixel shift from changing every comparison.

The picture must be at least 9 by 8. Below that some cells would be empty and the
comparison would not mean anything, so the hash raises instead.

## Step 2: positions

A 64-bit fingerprint is **not** a representation, and using one directly would be
a mistake:

- about half its bits are set, where a representation wants a few per cent;
- 64 bits cannot spread over a column population of any size;
- two fingerprints that differ in one bit are simply different — there is nothing
  graded to read off them.

So each fingerprint bit owns one position in the representation, and the
representation is those positions for the bits that are set:

```pony
let encoder = ImageEncoder(ImageEncoderParams(256, 64, 7))?
let active = encoder.encode(image)?    // 256 positions, one per set bit
```

Two fingerprints that disagree on `k` bits share all but `k` of their active
positions, so overlap falls away as the pictures get less alike. Positions are
drawn once, in the constructor, without repetition, so no two pictures share a
position by accident.

## What the example measures

[The picture similarity example](examples.md#picture-similarity) encodes one
picture, the same picture twice as wide, the same picture brighter, and a
different picture, then puts each representation through the spatial pooler:

```
picture           bits set  distance  columns  shared with the original
the original      10        0         18       18
twice the size    10        0         18       18
brighter          10        0         18       18
a different one   16        22        23       9
```

Size and brightness change nothing. The different picture disagrees on 22 of 64
fingerprint bits and survives as 9 shared columns out of 23.

## What it does not survive

- **Cropping.** Moving the frame changes which cells fall in which of the nine
  columns, so every comparison can change. PDQ, a 256-bit hash used for
  near-duplicate detection, is built to survive this; it would replace
  `DifferenceHash` without the encoder noticing, because the encoder only ever
  sees an `ImageFingerprint`.
- **Rotation**, for the same reason.
- **Reading a file.** Pony has no image decoder, so `ImageDecoder` is an
  interface with no implementation yet. Everything above it works on a
  `GrayscaleImage`, which the caller supplies.

Anything that decodes pixels — PNG, JPEG, or an FFI call to a C decoder — plugs
in at that one interface. A decoder is also where transparency has to be
composited against a background, before the reduction to brightness.

## Why not an embedding

Sign-binarised DINOv2 or CLIP vectors were considered and rejected. Hamming
distance stops tracking cosine distance near zero, so two unrelated pictures can
look adjacent, and it would pull in a PyTorch or ONNX runtime to replace a few
hundred lines of arithmetic.
