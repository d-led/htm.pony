use "../encoders"

primitive Synthetic
  """
  Pictures built in code, for the measurements that are about what a
  fingerprint does to pixels rather than about reading a file.

  Each one is a small grid of brightness with a structure at a known scale: a
  diagonal ramp, vertical bars, a smooth gradient, a ring, and a checkerboard.
  Between them they cover the things a fingerprint can be fooled by - a picture
  that is all one frequency, a picture with no edges at all, and one where the
  detail is as fine as the grid.

  Every picture is a whole number of the pattern's own period inside the frame,
  so the same picture at another size is the same picture rather than a
  different corner of one.
  """

  fun pattern(width: USize, height: USize): GrayscaleImage val ? =>
    """
    A diagonal ramp that wraps every two hundred levels.
    """
    filled(width, height, {(x: USize, y: USize): U8 =>
      (((x * 7) + (y * 13)) % 200).u8() })?

  fun stripes(width: USize, height: USize): GrayscaleImage val ? =>
    """
    Vertical bars three pixels wide, dark then light.
    """
    filled(width, height, {(x: USize, y: USize): U8 =>
      if ((x / 3) % 2) == 0 then 20 else 200 end })?

  fun gradient(width: USize, height: USize): GrayscaleImage val ? =>
    """
    A smooth left-to-right ramp, with no edge anywhere in it.
    """
    filled(width, height, {(x: USize, y: USize): U8 =>
      if width == 0 then 0
      else ((x * 255) / width).u8()
      end })?

  fun ring(width: USize, height: USize): GrayscaleImage val ? =>
    """
    A bright ring around the middle of the frame, and the middle left dark.
    """
    let centre = (width.f64() / 2.0, height.f64() / 2.0)
    let outer = (width.f64() / 2.0) * 0.9
    let inner = outer * 0.6

    filled(width, height, {(x: USize, y: USize): U8 =>
      let dx = x.f64() - centre._1
      let dy = y.f64() - centre._2
      let distance = ((dx * dx) + (dy * dy)).sqrt()
      if (distance > inner) and (distance < outer) then 220 else 30 end })?

  fun checker(width: USize, height: USize): GrayscaleImage val ? =>
    """
    Squares of eight pixels, alternating dark and light.
    """
    filled(width, height, {(x: USize, y: USize): U8 =>
      if (((x / 8) + (y / 8)) % 2) == 0 then 240 else 15 end })?

  fun filled(
    width: USize,
    height: USize,
    level: {(USize, USize): U8} val)
    : GrayscaleImage val ?
  =>
    """
    A picture whose every pixel is decided by where it is.
    """
    if (width == 0) or (height == 0) then error end

    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, width * height) end
    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = level(x, y)
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?
