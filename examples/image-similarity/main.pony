use "../../htm"
use "../../htm/encoders"
use "../../htm/measure"

actor Main
  """
  A picture, a fingerprint of it, a representation of that fingerprint, and a
  set of columns that recognise it.

  Four pictures are encoded: one, the same one twice as wide, the same one
  brighter, and a different one. The first three should come out identical and
  the fourth should not.

  Expect the first three to agree on every column and the fourth to share only
  part of them.
  """
  new create(env: Env) =>
    try
      let encoder = ImageEncoder(
        ImageEncoderParams(256, 64 where seed' = 7))?
      let pooler = SpatialPooler(SpatialPoolerConfig([64], [256]
        where global_inhibition' = true, num_active_columns_per_inh_area' = 16.0), 42)?

      let original = Pictures.pattern(18, 16)?
      let pictures: Array[(String, GrayscaleImage val)] = [
        ("the original", original)
        ("twice the size", Pictures.scaled(original, 2)?)
        ("brighter", Pictures.brighter(original, 30)?)
        ("a different one", Pictures.stripes(18, 16)?)
      ]

      let first = DifferenceHash.compute(original)?
      let base = pooler.compute(encoder.encode_fingerprint(first)?)?

      env.out.print("four pictures: one, the same twice as wide, the same")
      env.out.print("brighter, and a different one")
      env.out.print("")
      env.out.print(
        _pad("picture", 18) + _pad("bits set", 10) + _pad("distance", 10)
          + _pad("columns", 9) + "shared with the original")
      for picture in pictures.values() do
        (let name, let image) = picture
        let fingerprint = DifferenceHash.compute(image)?
        let active = encoder.encode_fingerprint(fingerprint)?
        let columns = pooler.compute(active)?

        env.out.print(
          _pad(name, 18)
            + _pad(fingerprint.active().string(), 10)
            + _pad(fingerprint.hamming(first)?.string(), 10)
            + _pad(columns.size().string(), 9)
            + _shared(base, columns).string())
      end

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun _shared(left: ReadSeq[USize], right: ReadSeq[USize]): USize =>
    var count: USize = 0
    for column in left.values() do
      if _contains(right, column) then count = count + 1 end
    end
    count

  fun _contains(values: ReadSeq[USize], wanted: USize): Bool =>
    for value in values.values() do
      if value == wanted then return true end
    end
    false

primitive Pictures
  """
  Pictures built in code, because reading a file needs a decoder and this
  example is about what happens after the pixels are there.
  """
  fun pattern(width: USize, height: USize): GrayscaleImage val ? =>
    let pixels: Array[U8] iso = recover iso Array[U8].init(0, width * height) end
    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = (((x * 7) + (y * 13)) % 200).u8()
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?

  fun stripes(width: USize, height: USize): GrayscaleImage val ? =>
    let pixels: Array[U8] iso = recover iso Array[U8].init(0, width * height) end
    var y: USize = 0
    while y < height do
      var x: USize = 0
      while x < width do
        pixels((y * width) + x)? = if ((x / 3) % 2) == 0 then 20 else 200 end
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(width, height, consume pixels)?

  fun scaled(image: GrayscaleImage val, factor: USize): GrayscaleImage val ? =>
    Distortions.scaled(image, factor)?

  fun brighter(image: GrayscaleImage val, by: U8): GrayscaleImage val ? =>
    Distortions.brighter(image, by)?
