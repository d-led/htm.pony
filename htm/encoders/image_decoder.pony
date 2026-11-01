primitive DecodeFailed

interface ImageDecoder
  """
  The one place a picture file is understood.

  Everything above this seam works on `GrayscaleImage` and knows nothing about
  file formats. Pony has no image decoder of its own, so a real PNG or JPEG
  decoder is the only part of this feature that needs an FFI call; the grayscale
  reduction, the resize, the hash and the mapping to positions are all plain
  arithmetic and are tested on pixel grids built in code.

  A decoder is expected to composite any transparency against a background
  before reducing to brightness, because an image with an alpha channel is two
  pictures at once otherwise.
  """
  fun decode(bytes: Array[U8] val): (GrayscaleImage val | DecodeFailed)
