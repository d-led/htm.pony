primitive DifferenceHash
  """
  A fingerprint of how brightness falls across a picture.

  The picture is reduced to a 9 by 8 grid by averaging every source cell, and
  each row is then read left to right: a bit is set where a cell is brighter
  than the one after it. That is 8 rows of 8 comparisons, so 64 bits.

  The reduction to 9 by 8 is what makes the fingerprint independent of the
  picture's size. A 200 by 200 image and a 2000 by 2000 image of the same scene
  average to nearly the same grid, and give the same bits.

  A stronger hash, such as PDQ, could replace this without the encoder noticing,
  because the encoder only sees an `ImageFingerprint`.
  """

  fun columns(): USize => 9

  fun rows(): USize => 8

  fun bits(): USize => 64

  fun compute(image: GrayscaleImage val): ImageFingerprint val ? =>
    let small = downsampled(image)?
    let result: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end

    var row: USize = 0
    while row < rows() do
      var column: USize = 0
      while column < (columns() - 1) do
        let left = small((row * columns()) + column)?
        let right = small((row * columns()) + column + 1)?
        try result((row * 8) + column)? = left > right end
        column = column + 1
      end
      row = row + 1
    end

    ImageFingerprint(consume result)

  fun downsampled(image: GrayscaleImage val): Array[F64] ? =>
    """
    The picture averaged into a 9 by 8 grid of brightness values.

    Averaging rather than sampling is what stops grain and a one pixel shift
    from changing every comparison. Fails when the picture is smaller than the
    grid, because then some cells would be empty and the comparison would not
    mean anything.
    """
    if (image.width < columns()) or (image.height < rows()) then error end
    Resample.block_average(image, columns(), rows())?
