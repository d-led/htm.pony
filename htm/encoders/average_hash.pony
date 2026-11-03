use "collections"

primitive AverageHash
  """
  A fingerprint of where the brightness sits in a picture: 256 bits, one per
  cell of a 16 by 16 grid.

  The picture is reduced to 16 by 16 by averaging every source cell, and each
  of those 256 values is then compared with the median of the 256: a bit is set
  where a cell is brighter than the picture's own middle. About half the bits
  are therefore set - a little fewer when several cells sit exactly on the
  median, as they do in a picture with flat regions - and a copy that is
  brighter or darker as a whole gives the same bits.

  This is the coarse band of a Haar transform of the picture, which is what an
  average hash is: the brightness laid out in a grid, with its own middle for a
  reference level. It is the other end of the cheap spectrum from
  `DifferenceHash`, which keeps the sign of the gradient between neighbours and
  throws the layout away. Neither is PDQ, whose low frequencies come from a
  cosine transform; this library keeps to additions so that its arithmetic is
  exact and can be predicted on paper.

  As with `DifferenceHash`, a stronger hash could take its place without the
  encoder noticing, because the encoder only ever sees an `ImageFingerprint`.
  """

  fun columns(): USize => 16

  fun rows(): USize => 16

  fun bits(): USize => 256

  fun compute(image: GrayscaleImage val): ImageFingerprint val ? =>
    let layout = Resample.block_average(image, columns(), rows())?
    let middle = Median.of(layout)?

    let result: Array[Bool] iso = recover iso Array[Bool].init(false, bits()) end
    var index: USize = 0
    for value in layout.values() do
      result(index)? = value > middle
      index = index + 1
    end
    ImageFingerprint(consume result)

primitive Median
  """
  The middle value of a set of numbers, which is the reference level an average
  hash compares its cells with: half a picture is brighter than its own middle,
  however it is exposed.
  """
  fun of(values: ReadSeq[F64]): F64 ? =>
    """
    Fails on no values, because a median of nothing is not a level.
    """
    if values.size() == 0 then error end

    let sorted: Array[F64] = Array[F64](values.size())
    for value in values.values() do
      sorted.push(value)
    end
    Sort[Array[F64], F64](sorted)

    let middle = sorted.size() / 2
    if (sorted.size() % 2) == 1 then
      sorted(middle)?
    else
      (sorted(middle - 1)? + sorted(middle)?) / 2.0
    end
