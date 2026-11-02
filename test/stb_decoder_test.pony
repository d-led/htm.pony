use "pony_test"
use "files"
use "../htm/encoders"
use "../htm/encoders/stb"

primitive PngFixture
  """
  A PNG written by hand, 18 by 16, whose brightness follows the same rule as the
  picture built in code, so the two can be compared.
  """
  fun bytes(env: Env): Array[U8] val =>
    let path = FilePath(FileAuth(env.root), "fixtures/pattern.png")
    let file = File(path)
    let content: Array[U8] val = file.read(file.size())
    content

  fun picture(width: USize, height: USize): GrayscaleImage val ? =>
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

primitive BmpFixture
  """
  A 24-bit BMP built byte by byte, so a test can name any size it likes without
  carrying a file. `stb_image` reads the dimensions from the header alone, which
  is what makes a picture of any size sayable in fifty-four bytes.
  """
  fun bytes(width: USize, height: USize, with_pixels: Bool): Array[U8] val =>
    let row = (((width * 3) + 3) / 4) * 4
    let pixels = if with_pixels then row * height else 0 end

    var values: Array[U8] iso = recover iso Array[U8] end
    values.push(0x42)                          // 'B'
    values.push(0x4d)                          // 'M'
    values = _u32(consume values, (54 + pixels).u32())   // file size
    values = _u32(consume values, 0)                     // reserved
    values = _u32(consume values, 54)                    // where the pixels start
    values = _u32(consume values, 40)                    // size of the rest
    values = _u32(consume values, width.u32())
    values = _u32(consume values, height.u32())          // positive: rows run up
    values = _u16(consume values, 1)                     // planes
    values = _u16(consume values, 24)                    // bits per pixel
    values = _u32(consume values, 0)                     // not compressed
    values = _u32(consume values, pixels.u32())
    values = _u32(consume values, 2835)                  // pixels per metre, x
    values = _u32(consume values, 2835)                  // pixels per metre, y
    values = _u32(consume values, 0)                     // colours used
    values = _u32(consume values, 0)                     // colours that matter

    var pushed: USize = 0
    while pushed < pixels do
      values.push(200)                   // one brightness, in all three channels
      pushed = pushed + 1
    end

    consume values

  fun _u32(values: Array[U8] iso, value: U32): Array[U8] iso^ =>
    values.push((value and 0xff).u8())
    values.push(((value >> 8) and 0xff).u8())
    values.push(((value >> 16) and 0xff).u8())
    values.push(((value >> 24) and 0xff).u8())
    consume values

  fun _u16(values: Array[U8] iso, value: U16): Array[U8] iso^ =>
    values.push((value and 0xff).u8())
    values.push(((value >> 8) and 0xff).u8())
    consume values

class StbDecoderTest is TestList
  fun name(): String => "Picture file decoder"

  fun tag tests(test: PonyTest) =>
    test(_APngDecodesToItsPixels)
    test(_ADecodedPictureHashesLikeTheSamePictureInCode)
    test(_SomethingThatIsNotAPictureIsRefused)
    test(_ABmpDecodesSoTheHeaderUsedBelowIsARealOne)
    test(_APictureTooLargeToMakeIsRefusedFromItsHeader)

class iso _APngDecodesToItsPixels is UnitTest
  fun name(): String => "a png decodes to its pixels"

  fun apply(h: TestHelper) ? =>
    match StbDecoder.decode(PngFixture.bytes(h.env))
    | let image: GrayscaleImage val =>
      h.assert_eq[USize](18, image.width)
      h.assert_eq[USize](16, image.height)
      h.assert_eq[U8](0, image(0, 0)?)
      h.assert_eq[U8](7, image(1, 0)?)
      h.assert_eq[U8](13, image(0, 1)?)
    else
      h.fail("a valid png should decode")
    end

class iso _ADecodedPictureHashesLikeTheSamePictureInCode is UnitTest
  fun name(): String => "a decoded picture hashes like the same picture built in code"

  fun apply(h: TestHelper) ? =>
    match StbDecoder.decode(PngFixture.bytes(h.env))
    | let decoded: GrayscaleImage val =>
      let from_file = DifferenceHash.compute(decoded)?
      let from_code = DifferenceHash.compute(PngFixture.picture(18, 16)?)?
      h.assert_eq[USize](0, from_file.hamming(from_code)?)
    else
      h.fail("a valid png should decode")
    end

class iso _SomethingThatIsNotAPictureIsRefused is UnitTest
  fun name(): String => "something that is not a picture is refused"

  fun apply(h: TestHelper) =>
    let not_a_picture: Array[U8] val = recover val [1; 2; 3; 4; 5] end

    match StbDecoder.decode(not_a_picture)
    | DecodeFailed => h.complete(true)
    else
      h.fail("bytes that are not a picture should not decode")
    end

class iso _ABmpDecodesSoTheHeaderUsedBelowIsARealOne is UnitTest
  fun name(): String => "a bmp decodes, so the header the size test relies on is a real one"

  fun apply(h: TestHelper) ? =>
    match StbDecoder.decode(BmpFixture.bytes(8, 8, true))
    | let image: GrayscaleImage val =>
      h.assert_eq[USize](8, image.width)
      h.assert_eq[USize](8, image.height)
      h.assert_eq[U8](200, image(4, 4)?)
      h.complete(true)
    else
      h.fail("a valid bmp should decode")
    end

class iso _APictureTooLargeToMakeIsRefusedFromItsHeader is UnitTest
  fun name(): String => "a picture too large to make is refused from its header"

  fun apply(h: TestHelper) =>
    // Four hundred million pixels in fifty-four bytes: the file is fifteen
    // bytes of header and a number. Decoding it would mean allocating a
    // gigabyte and a half inside C, which is the case the limit exists for.
    h.assert_true((20_000 * 20_000) > StbDecoder.pixel_limit(),
      "the size below is above what the decoder will make")

    match StbDecoder.decode(BmpFixture.bytes(20_000, 20_000, false))
    | DecodeFailed => h.complete(true)
    else
      h.fail("a picture of four hundred million pixels should be refused")
    end
