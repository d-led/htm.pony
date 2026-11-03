use "pony_test"
use "../htm/encoders"

primitive TestImages
  """
  Pictures built in code, so the encoder can be tested without a file format.
  """

  fun pattern(width: USize, height: USize): GrayscaleImage val ? =>
    """
    Brightness that varies along both axes, staying below 200 so a brightness
    shift in a test has room to move.
    """
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
    """
    A different picture: vertical bands, so its brightness falls where the
    pattern rises.
    """
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
    """
    The same picture with every pixel repeated, so it covers more area.
    """
    let width = image.width * factor
    let height = image.height * factor
    let pixels: Array[U8] iso = recover iso Array[U8].init(0, width * height) end
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

  fun brighter(image: GrayscaleImage val, by: U8): GrayscaleImage val ? =>
    let pixels: Array[U8] iso = recover iso Array[U8].init(0, image.width * image.height) end
    var y: USize = 0
    while y < image.height do
      var x: USize = 0
      while x < image.width do
        let value = image(x, y)?.u16() + by.u16()
        pixels((y * image.width) + x)? = if value > 255 then 255 else value.u8() end
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(image.width, image.height, consume pixels)?

  fun mirrored(image: GrayscaleImage val): GrayscaleImage val ? =>
    let pixels: Array[U8] iso = recover iso Array[U8].init(0, image.width * image.height) end
    var y: USize = 0
    while y < image.height do
      var x: USize = 0
      while x < image.width do
        pixels((y * image.width) + x)? = image(image.width - 1 - x, y)?
        x = x + 1
      end
      y = y + 1
    end
    GrayscaleImage(image.width, image.height, consume pixels)?

  fun encoder(bits: USize = 64): ImageEncoder ? =>
    ImageEncoder(ImageEncoderParams(1024, bits where seed' = 42))?

class ImageEncoderTest is TestList
  fun name(): String => "Image encoder"

  fun tag tests(test: PonyTest) =>
    test(_TheSamePictureGivesTheSameRepresentation)
    test(_TheSamePictureAtTwiceTheSizeGivesTheSameRepresentation)
    test(_ABrighterCopyGivesTheSameRepresentation)
    test(_OneBitOfDifferenceCostsOnePosition)
    test(_ADifferentPictureSharesFewPositions)
    test(_AMirrorImageSharesFewPositions)
    test(_ARepresentationNarrowerThanTheFingerprintIsRefused)
    test(_AFingerprintOfTheWrongSizeIsRefused)

class iso _TheSamePictureGivesTheSameRepresentation is UnitTest
  fun name(): String => "the same picture gives the same representation"

  fun apply(h: TestHelper) ? =>
    let image = TestImages.pattern(18, 16)?
    let encoder = TestImages.encoder()?

    let first = encoder.encode(image)?
    let second = encoder.encode(image)?

    h.assert_array_eq[Bool](first, second)

class iso _TheSamePictureAtTwiceTheSizeGivesTheSameRepresentation is UnitTest
  fun name(): String => "the same picture at twice the size gives the same representation"

  fun apply(h: TestHelper) ? =>
    let small = TestImages.pattern(18, 16)?
    let large = TestImages.scaled(small, 2)?
    let encoder = TestImages.encoder()?

    let first = encoder.encode(small)?
    let second = encoder.encode(large)?

    h.assert_array_eq[Bool](first, second)

class iso _ABrighterCopyGivesTheSameRepresentation is UnitTest
  fun name(): String => "a brighter copy of a picture gives the same representation"

  fun apply(h: TestHelper) ? =>
    let image = TestImages.pattern(18, 16)?
    let brighter = TestImages.brighter(image, 30)?
    let encoder = TestImages.encoder()?

    let first = encoder.encode(image)?
    let second = encoder.encode(brighter)?

    h.assert_array_eq[Bool](first, second)

class iso _OneBitOfDifferenceCostsOnePosition is UnitTest
  fun name(): String => "two fingerprints one bit apart share all but one position"

  fun apply(h: TestHelper) ? =>
    let encoder = TestImages.encoder(12)?
    let here = ImageFingerprint.from_u64(0b111111000000, 12)
    let one_apart = ImageFingerprint.from_u64(0b111110000000, 12)

    h.assert_eq[USize](1, here.hamming(one_apart)?)
    h.assert_eq[USize](5, encoder.overlap(encoder.encode_fingerprint(here)?, encoder.encode_fingerprint(one_apart)?))

class iso _ADifferentPictureSharesFewPositions is UnitTest
  fun name(): String => "a different picture shares few positions"

  fun apply(h: TestHelper) ? =>
    let encoder = TestImages.encoder()?
    let first = encoder.encode(TestImages.pattern(18, 16)?)?
    let second = encoder.encode(TestImages.stripes(18, 16)?)?

    h.assert_true(
      encoder.overlap(first, second) < 32,
      "two unlike pictures should share fewer than half their positions")

class iso _AMirrorImageSharesFewPositions is UnitTest
  fun name(): String => "a picture and its mirror image share few positions"

  fun apply(h: TestHelper) ? =>
    let encoder = TestImages.encoder()?
    let image = TestImages.pattern(18, 16)?
    let mirrored = TestImages.mirrored(image)?

    h.assert_true(
      encoder.overlap(encoder.encode(image)?, encoder.encode(mirrored)?) < 32,
      "a mirror image should not have most of the same positions")

class iso _ARepresentationNarrowerThanTheFingerprintIsRefused is UnitTest
  fun name(): String => "a representation narrower than the fingerprint is refused"

  fun apply(h: TestHelper) =>
    try
      ImageEncoder(ImageEncoderParams(32, 64 where seed' = 42))?
      h.fail("an encoder narrower than its fingerprint should not be built")
    end

class iso _AFingerprintOfTheWrongSizeIsRefused is UnitTest
  fun name(): String => "a fingerprint of the wrong size is refused"

  fun apply(h: TestHelper) ? =>
    let encoder = TestImages.encoder(64)?

    try
      encoder.encode_fingerprint(ImageFingerprint.from_u64(0xFF, 8))?
      h.fail("a fingerprint of another size should not be accepted")
    end
