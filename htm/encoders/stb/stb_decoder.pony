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

// The same three slots, filled from the header alone: no pixels are decoded and
// nothing is allocated for them.
use @stbi_info_from_memory[I32](
  buffer: Pointer[U8] tag,
  length: I32,
  width: Pointer[I32] tag,
  height: Pointer[I32] tag,
  channels: Pointer[I32] tag)

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

  Because that call cannot be interrupted, the header is read first and a
  picture larger than `pixel_limit` is refused before it is decoded: a few
  hundred bytes of compressed data can name a picture of any size at all, and
  obeying it would cost the memory and the time it asks for.
  """

  fun pixel_limit(): USize =>
    """
    The most pixels this decoder will make - 4096 by 4096, sixteen megabytes of
    brightness.

    A picture above this is not refused because the decoders above could not
    handle it, but because the work is unbounded: the decode happens inside C, on
    the thread that asked for it, and nothing can call it off. Sixteen megabytes
    is far more than an encoder that turns a picture into a few thousand bits has
    any use for, and small enough that the call returns long before a caller
    waiting on a pooler would wonder.
    """
    16_777_216

  fun decode(bytes: Array[U8] val): (GrayscaleImage val | DecodeFailed) =>
    if bytes.size() == 0 then return DecodeFailed end
    if bytes.size() > 2_000_000_000 then return DecodeFailed end

    let size = Array[I32].init(0, 3)
    let length = bytes.size().i32()

    if not _picture_fits(bytes, length, size) then return DecodeFailed end

    let data = @stbi_load_from_memory(
      bytes.cpointer(), length, _at(size, 0), _at(size, 1), _at(size, 2), 1)

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

  fun _picture_fits(bytes: Array[U8] val, length: I32, size: Array[I32] ref): Bool =>
    """
    Whether the picture this file declares is one this decoder will make, read
    from the header and decided before anything is allocated for the pixels.
    """
    let read = @stbi_info_from_memory(
      bytes.cpointer(), length, _at(size, 0), _at(size, 1), _at(size, 2))
    if read == 0 then return false end

    let width = _dimension(size, 0)
    let height = _dimension(size, 1)
    if (width == 0) or (height == 0) then return false end
    if (width > pixel_limit()) or (height > pixel_limit()) then return false end
    (width * height) <= pixel_limit()

  fun _at(values: Array[I32] ref, index: USize): Pointer[I32] tag =>
    values.cpointer(index)

  fun _dimension(values: Array[I32] ref, index: USize): USize =>
    """
    stb writes width, height and channels into the three slots; a slot that was
    never written, or written with a negative value, is a dimension of nothing.
    """
    try
      let value = values(index)?
      if value > 0 then value.usize() else 0 end
    else
      0
    end
