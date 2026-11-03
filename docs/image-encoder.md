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

## Measured on a corpus of real photographs

Four pictures built in code say the hash does the two things it was designed to
do. They do not say whether it can tell pictures of one thing from pictures of
another, which is the question that decides whether it is worth keeping.

[`examples/image-retrieval`](examples.md#does-the-representation-find-pictures-of-the-same-kind)
asks it of imagenette, ten classes of real photographs. No corpus is stored in
this repository: `scripts/fetch-images.sh` downloads one into the ignored
`data/` directory, and the example reads whatever directory of class
directories it is given, so a corpus of your own is measured by the same code.

The answer, on 300 pictures and 300 queries:

```
                                this corpus by chance
nearest is a classmate          17.3%       9.7%
a classmate in the first five   60.0%       40.2%
mean distance, own class        31.2
mean distance, other classes    31.7
```

Nearly twice the chance rate is a real signal and not retrieval. Both mean
distances sit near thirty-two of sixty-four bits, which is what two unrelated
fingerprints look like, so the ranking does not come from classmates being
close. A difference hash keeps the coarse run of brightness across nine cells
and throws the rest away; that is why size and brightness cannot move it, and
also why it cannot tell a golf ball from a gas pump.

## Drift, against a second hash

The question a hash is for is not whether it can tell classes apart but whether
the *same* picture still fingerprints as itself after it has been resized,
re-exposed or recompressed. `examples/image-robustness` measures that, on
pictures built in code so that the answer is reproducible, and it measures a
second hash beside it: `AverageHash`, a 256-bit layout of 16 by 16 block
averages each compared with the picture's own median. The two are the ends of
the cheap spectrum - gradients against layout - and neither is PDQ, whose low
frequencies come from a cosine transform; that transform needs trigonometry
this library does not carry, and a use has not yet earned it.

```
                              difference   average
brighter, forty levels        0.0%         0.0%
twice the size                5.3%         0.0%
half the size                 3.1%         0.0%
cropped, a twentieth a side   23.8%        19.1%
grain, 10 levels              5.3%         10.2%
a different picture           45.0%        49.3%
```

Brightness costs neither anything, and by construction: the difference hash
keeps only the sign of the gradient, and a level added to every pixel cancels;
the average hash compares against the median, which moves with the picture.
Size costs the average hash nothing and the difference hash a few bits because
sixteen cells into ninety-six pixels lands on a boundary and nine does not.
Grain costs the difference hash less, because its cells are larger and average
the grain away first. Cropping costs both about half of what being a different
picture costs - see below.

## What it does not survive

- **Cropping.** Moving the frame changes which cells fall in which of the nine
  columns, so comparisons change: measured, a crop of a twentieth a side costs a
  fifth of the bits, which is about half of what being a different picture
  costs. PDQ, a 256-bit hash used for near-duplicate detection, is built to
  survive this; it would replace `DifferenceHash` without the encoder noticing,
  because the encoder only ever sees an `ImageFingerprint`.
- **Rotation**, for the same reason.

## Reading a file

`StbDecoder` reads PNG, JPEG, BMP and GIF through
[stb_image](https://github.com/nothings/stb), a single public-domain header. It
is the only implementation of `ImageDecoder`, and the only FFI call in the
library:

```pony
match StbDecoder.decode(bytes)
| let image: GrayscaleImage val => encoder.encode(image)?
| DecodeFailed => /* not a picture, or a broken one */
end
```

The bytes are asked of stb as one channel per pixel, so the reduction to
brightness happens in C next to the decoder rather than in Pony. stb allocates
the pixels; they are copied into a Pony array and freed on every path, including
the ones that reject the file.

Two consequences of going through stb are worth knowing. An image with an alpha
channel loses it: transparency is not composited against a background, so a
transparent region contributes whatever colour it was stored with. And a format
stb does not know — TIFF, WebP, AVIF — is refused rather than guessed at.

The header is compiled in with `STBI_NO_STDIO` and `STBI_ONLY_PNG`,
`STBI_ONLY_JPEG`, `STBI_ONLY_BMP`, `STBI_ONLY_GIF`, so the binary carries four
decoders and no file handling of its own.

Everything above the decoder works on a `GrayscaleImage` and knows nothing about
file formats, which is why the fingerprint, the resize, the hash and the mapping
to positions are all tested on pixel grids built in code. The decoder is tested
against a PNG written by hand — eighteen by sixteen pixels, in `test/fixtures/` —
and asserts both the pixels and that the decoded picture hashes the same as the
same picture built in code.

## Why not an embedding

Sign-binarised DINOv2 or CLIP vectors were considered and rejected. Hamming
distance stops tracking cosine distance near zero, so two unrelated pictures can
look adjacent, and it would pull in a PyTorch or ONNX runtime to replace a few
hundred lines of arithmetic.
