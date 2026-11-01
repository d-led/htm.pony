use ".."

// stb_image, asked for one byte per pixel so C does the colour reduction.
use @stbi_load_from_memory[Pointer[U8] ref](
  buffer: Pointer[U8] tag,
  length: I32,
  width: Pointer[I32] tag,
  height: Pointer[I32] tag,
  channels: Pointer[I32] tag,
  wanted_channels: I32)
use @stbi_image_free[None](data: Pointer[U8] tag)

use @htm_copy_bytes[None](
  destination: Pointer[U8] tag,
  source: Pointer[U8] tag,
  length: USize)

primitive StbDecoder is ImageDecoder
  """
  Reads PNG, JPEG, BMP and GIF through stb_image.

  stb is asked for one channel per pixel, so the colour reduction happens in C
  next to the decoder rather than here. Pixels arrive as brightness with
  transparency already discarded by the library, which is the one place this
  decoder makes a choice the caller cannot see: an image with an alpha channel
  loses it, and its transparent parts take whatever colour they were stored with.

  The bytes are handed to C as a pointer into the array, so the array must stay
  alive across the call; it does, because the call is synchronous.
  """

  fun decode(bytes: Array[U8] val): (GrayscaleImage val | DecodeFailed) =>
    if bytes.size() == 0 then return DecodeFailed end
    if bytes.size() > 2_000_000_000 then return DecodeFailed end

    let size = Array[I32].init(0, 3)
    let data = @stbi_load_from_memory(
      bytes.cpointer(), bytes.size().i32(), _at(size, 0), _at(size, 1), _at(size, 2), 1)

    if data.is_null() then return DecodeFailed end

    let width = _dimension(size, 0)
    let height = _dimension(size, 1)

    if (width == 0) or (height == 0) then
      @stbi_image_free(data)
      return DecodeFailed
    end

    let pixels: Array[U8] iso = recover iso Array[U8].init(0, width * height) end
    @htm_copy_bytes(pixels.cpointer(), data, width * height)
    @stbi_image_free(data)

    try
      return GrayscaleImage(width, height, consume pixels)?
    else
      return DecodeFailed
    end

  fun _at(values: Array[I32] ref, index: USize): Pointer[I32] tag =>
    values.cpointer(index)

  fun _dimension(values: Array[I32] ref, index: USize): USize =>
    """
    stb writes width, height, channels into the three slots; a slot that was
    never written stays zero and reads as a dimension of nothing.
    """
    try values(index)?.usize() else 0 end
