primitive DateField
  """
  One field of a date, encoded over its own range: which encoder it is, where in
  the vector it is written, and how wide it is.

  A field whose width is nought is not encoded at all, and is answered with a
  no-op encoder and an offset of nought. Every field in a date is built the same
  way - a scalar encoder over a range, at a width and a radius - so the one place
  that differs is what the encoder is given, not how it is made.
  """
  fun build(
    width: USize,
    max: F64,
    name: String,
    radius: F64,
    periodic: Bool,
    offset: USize)
    : (SomeScalarEncoder, USize, USize) ?
  =>
    if width == 0 then return (NoOpScalarEncoder, 0, 0) end

    let params = ScalarEncoderParams(
      width,
      0,
      max
    where
      name' = name,
      radius' = radius,
      periodic' = periodic
    )

    let encoder = ScalarEncoder(params)?
    (encoder, offset, encoder.n)
