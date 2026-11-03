use "pony_test"
use "../htm/encoders"
use "../htm/encoders/stb"

primitive EncoderFixture
  """
  The picture the decoder tests already carry, turned into bits in one process,
  so the actor has something to be compared with.
  """
  fun params(): ImageEncoderParams val =>
    ImageEncoderParams(1024, 64 where seed' = 7)

  fun bits(env: Env): Array[Bool] val ? =>
    let encoder = ImageEncoder(params())?
    match StbDecoder.decode(PngFixture.bytes(env))
    | let image: GrayscaleImage val => _frozen(encoder.encode(image)?)
    else error
    end

  fun _frozen(values: Array[Bool]): Array[Bool] val =>
    let copy: Array[Bool] iso = recover iso Array[Bool] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

actor BitsSink is PictureSink
  """
  Compares every answer with what one process said about the same picture, in the
  order the answers arrive.
  """
  let _h: TestHelper
  let _expected: Array[Array[Bool] val] val
  var _seen: USize = 0

  new create(h: TestHelper, expected: Array[Array[Bool] val] val) =>
    _h = h
    _expected = expected

  be pictured(fingerprint: ImageFingerprint val, bits: Array[Bool] val) =>
    try
      let want = _expected(_seen)?
      _h.assert_eq[USize](want.size(), bits.size(), "the representation is the right size")
      var index: USize = 0
      while index < want.size() do
        _h.assert_eq[Bool](want(index)?, bits(index)?, "the same bit, in the same place")
        index = index + 1
      end
    end

    _seen = _seen + 1
    if _seen == _expected.size() then
      _h.complete(true)
    end

  be refused() =>
    _h.fail("a picture that should decode was refused")

actor RefusalSink is PictureSink
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be pictured(fingerprint: ImageFingerprint val, bits: Array[Bool] val) =>
    _h.fail("bytes that are not a picture should not be pictured")

  be refused() =>
    _h.complete(true)

class PictureEncoderTest is TestList
  fun name(): String => "Picture encoder"

  fun tag tests(test: PonyTest) =>
    test(_AnActorEncodesAPictureAsOneProcessDoes)
    test(_ABytesThatAreNotAPictureIsRefused)
    test(_TwoPicturesInARowAreBothAnswered)

class iso _AnActorEncodesAPictureAsOneProcessDoes is UnitTest
  fun name(): String => "a picture goes through an actor to the same bits as one process"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let wanted = EncoderFixture.bits(h.env)?
    let expected: Array[Array[Bool] val] val = recover val [wanted] end

    PictureEncoder(ImageEncoder(EncoderFixture.params())?)
      .picture(PngFixture.bytes(h.env), BitsSink(h, expected))

class iso _ABytesThatAreNotAPictureIsRefused is UnitTest
  fun name(): String => "bytes that are not a picture are refused"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let not_a_picture: Array[U8] val = recover val [1; 2; 3; 4; 5] end
    PictureEncoder(ImageEncoder(EncoderFixture.params())?)
      .picture(not_a_picture, RefusalSink(h))

class iso _TwoPicturesInARowAreBothAnswered is UnitTest
  fun name(): String => "two pictures pushed one after the other are both answered"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let wanted = EncoderFixture.bits(h.env)?
    let expected: Array[Array[Bool] val] val = recover val [wanted; wanted] end

    let encoder = PictureEncoder(ImageEncoder(EncoderFixture.params())?)
    let bytes = PngFixture.bytes(h.env)
    let answers = BitsSink(h, expected)

    encoder.picture(bytes, answers)
    encoder.picture(bytes, answers)
