class val GrayscaleImage
  """
  A picture reduced to one brightness per pixel, one byte each.

  This is what an encoder works on. Turning a file into one is the decoder's
  job: `ImageDecoder` is the seam, and nothing above it knows what format the
  picture came from.
  """
  let width: USize
  let height: USize
  let _pixels: Array[U8] val

  new val create(width': USize, height': USize, pixels: Array[U8] val) ? =>
    if (width' == 0) or (height' == 0) then error end
    if (width' * height') != pixels.size() then error end
    width = width'
    height = height'
    _pixels = pixels

  new val from_rows(rows: Array[Array[U8]] val) ? =>
    """
    Build from one row per line, all rows the same length.
    """
    if rows.size() == 0 then error end
    let row_width = rows(0)?.size()
    if row_width == 0 then error end

    let pixels: Array[U8] iso = recover iso Array[U8] end
    for row in rows.values() do
      if row.size() != row_width then error end
      for value in row.values() do
        pixels.push(value)
      end
    end

    width = row_width
    height = rows.size()
    _pixels = consume pixels

  fun apply(x: USize, y: USize): U8 ? =>
    """
    The brightness at one position. Fails outside the picture.
    """
    if (x >= width) or (y >= height) then error end
    _pixels((y * width) + x)?
