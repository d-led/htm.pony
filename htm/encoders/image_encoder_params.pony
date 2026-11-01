class val ImageEncoderParams
  """
  The shape of an image representation.

  `width` is how many positions the representation has, and `bits` is how many
  the fingerprint has; each fingerprint bit owns one position, so `width` has to
  be at least `bits`. The `seed` decides which positions, and the same seed
  always decides the same ones.
  """
  let width: USize
  let bits: USize
  let seed: U64

  new val create(width': USize = 1024, bits': USize = 64, seed': U64 = 42) =>
    width = width'
    bits = bits'
    seed = seed'
