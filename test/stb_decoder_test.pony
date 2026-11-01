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

class StbDecoderTest is TestList
  fun name(): String => "Picture file decoder"

  fun tag tests(test: PonyTest) =>
    test(_APngDecodesToItsPixels)
    test(_ADecodedPictureHashesLikeTheSamePictureInCode)
    test(_SomethingThatIsNotAPictureIsRefused)

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
