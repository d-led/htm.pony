use "random"

use "../encoders"

primitive Distortions
  """
  The things that happen to a picture between one copy of it and the next.

  Each of these takes a picture and gives another one, so a fingerprint taken
  before and after says how far apart the two look to it. They are deliberately
  the distortions a photograph meets in ordinary use - it is resized, it is
  exposed differently, it is cropped, it is noisy - rather than the ones a
  benchmark finds convenient.
  """

  fun brighter(image: GrayscaleImage val, by: U8): GrayscaleImage val ? =>
    """
    The same picture exposed `by` levels brighter, held at white rather than
    wrapping round.
    """
    changed(image, {(value: U8): U8 =>
      let lifted = value.u16() + by.u16()
      if lifted > 255 then 255 else lifted.u8() end })?

  fun darker(image: GrayscaleImage val, by: U8): GrayscaleImage val ? =>
    """
    The same picture exposed `by` levels darker, held at black.
    """
    changed(image, {(value: U8): U8 =>
      if value < by then 0 else value - by end })?

  fun scaled(image: GrayscaleImage val, factor: USize): GrayscaleImage val ? =>
    """
    The same picture `factor` times as wide and as tall, each pixel of it
    repeated, which is what the fingerprint sees as a size that does not
    matter.
    """
    if factor == 0 then error end

    let width = image.width * factor
    let height = image.height * factor
    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, width * height) end

    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = image(x / factor, y / factor)?
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?

  fun shrunk(image: GrayscaleImage val, factor: USize): GrayscaleImage val ? =>
    """
    The same picture `factor` times smaller, each new pixel the average of the
    block it replaces: what a photograph looks like once it has been sent
    somewhere and resized on the way.
    """
    if factor == 0 then error end
    if (image.width < factor) or (image.height < factor) then error end

    let width = image.width / factor
    let height = image.height / factor
    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, width * height) end

    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = _block_average(image, x, y, factor)?
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?

  fun _block_average(
    image: GrayscaleImage val,
    x: USize,
    y: USize,
    factor: USize)
    : U8 ?
  =>
    var total: USize = 0
    var row: USize = 0
    while row < factor do
      var column: USize = 0
      while column < factor do
        total = total + image((x * factor) + column, (y * factor) + row)?.usize()
        column = column + 1
      end
      row = row + 1
    end
    (total / (factor * factor)).u8()

  fun cropped(image: GrayscaleImage val, by: USize): GrayscaleImage val ? =>
    """
    The same picture with `by` pixels taken off every side: what a photograph
    looks like when the frame moved.
    """
    if (by == 0) or (by >= image.width) or (by >= image.height) then error end

    let width = image.width - (by * 2)
    let height = image.height - (by * 2)
    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, width * height) end

    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = image(x + by, y + by)?
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?

  fun noisy(
    image: GrayscaleImage val,
    amount: USize,
    random: Rand ref)
    : GrayscaleImage val ?
  =>
    """
    The same picture with `amount` levels of grain either way, drawn from the
    caller's generator so that a run can be repeated.
    """
    let spread: I32 = amount.i32()
    let levels: U64 = (amount * 2).u64()
    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, image.width * image.height) end

    var y: USize = 0
    while y < image.height do
      var x: USize = 0
      while x < image.width do
        let grain: I32 =
          if spread == 0 then 0
          else random.int(levels).i32() - spread
          end
        pixels((y * image.width) + x)? = _level(image(x, y)?.i32() + grain)
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(image.width, image.height, consume pixels)?

  fun _level(value: I32): U8 =>
    """
    A brightness held between black and white rather than wrapping round.
    """
    if value < 0 then 0
    elseif value > 255 then 255
    else value.u8()
    end

  fun changed(
    image: GrayscaleImage val,
    what: {(U8): U8} val)
    : GrayscaleImage val ?
  =>
    """
    The same picture with every pixel put through `what`.
    """
    let pixels: Array[U8] iso =
      recover iso Array[U8].init(0, image.width * image.height) end

    var y: USize = 0
    while y < image.height do
      var x: USize = 0
      while x < image.width do
        pixels((y * image.width) + x)? = what(image(x, y)?)
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(image.width, image.height, consume pixels)?
