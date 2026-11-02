use "collections"
use "pony_test"
use "../htm/encoders"
use "../htm/util"

// htm.core's `SimHashDocumentEncoder` and the tests beside it:
// bindings/py/tests/encoders/simhash_document_encoder_test.py. The golden-bits
// test is not ported - it pins which bits a SHAKE256 digest produces, and this
// encoder has its own digest. What is ported is what the encoding is for: words
// are what make documents alike, and alike documents overlap.

class SimHashEncodingTest is TestList
  fun name(): String => "SimHash document encoder"

  fun tag tests(test: PonyTest) =>
    test(_DocumentsThatShareWordsOverlapMore)
    test(_AnEmptyDocumentEncodesNothing)
    test(_TheEncodingHasAsManyActiveBitsAsAsked)
    test(_TheSameDocumentAlwaysEncodesTheSameWay)
    test(_CapitalsDoNotMatterUnlessAsked)
    test(_AnExcludedWordIsNotCounted)
    test(_AWordRepeatedManyTimesCountsUpToTheCeiling)
    test(_LettersBringSimilarWordsTogether)
    test(_OneLetterChangesAlmostEveryBitOfADigest)

primitive SimHashFixture
  fun encoder(
    size: USize = 400,
    active_bits: USize = 20,
    token_similarity: Bool = false,
    case_sensitive: Bool = false,
    frequency_ceiling: USize = 0,
    excludes: Array[String] val = recover val Array[String] end)
    : SimHashDocumentEncoder ?
  =>
    SimHashDocumentEncoder(
      SimHashParams(size, active_bits, token_similarity, case_sensitive,
        frequency_ceiling, 0, excludes)?)

  fun overlap(left: Array[Bool] val, right: Array[Bool] val): USize =>
    var common: USize = 0
    var index: USize = 0
    while index < left.size() do
      if (try left(index)? else false end) and
        (try right(index)? else false end)
      then
        common = common + 1
      end
      index = index + 1
    end
    common

class iso _DocumentsThatShareWordsOverlapMore is UnitTest
  fun name(): String => "documents that share words overlap more"

  fun apply(h: TestHelper) ? =>
    let encoder = SimHashFixture.encoder()?
    let sky = encoder.encode("The sky is beautiful today")?
    let sun = encoder.encode("The sun is beautiful today")?
    let homework = encoder.encode("Who did my homework today")?

    let near = SimHashFixture.overlap(sky, sun)
    let far = SimHashFixture.overlap(sun, homework)

    h.log("four words in common: " + near.string() + ", one: " + far.string())
    h.assert_true(near > far, "a word apart beats four words apart")

class iso _AnEmptyDocumentEncodesNothing is UnitTest
  fun name(): String => "a document with no words encodes to nothing"

  fun apply(h: TestHelper) ? =>
    let encoder = SimHashFixture.encoder()?
    let nothing = encoder.encode("")?
    let spaces = encoder.encode("    ")?

    h.assert_eq[USize](400, nothing.size())
    h.assert_eq[USize](0, _count(nothing))
    h.assert_eq[USize](0, _count(spaces))

  fun _count(bits: Array[Bool] val): USize =>
    var set: USize = 0
    for bit in bits.values() do
      if bit then set = set + 1 end
    end
    set

class iso _TheEncodingHasAsManyActiveBitsAsAsked is UnitTest
  fun name(): String => "the encoding sets the number of bits it is asked for"

  fun apply(h: TestHelper) ? =>
    let encoder = SimHashFixture.encoder(400, 20)?
    h.assert_eq[USize](400, encoder.width())
    h.assert_eq[USize](20, _set(encoder.encode("abcde fghij klmno")?))

    let sparse = SimHashFixture.encoder(400, 13)?
    h.assert_eq[USize](13, _set(sparse.encode("abcde fghij klmno")?))

  fun _set(bits: Array[Bool] val): USize =>
    var set: USize = 0
    for bit in bits.values() do
      if bit then set = set + 1 end
    end
    set

class iso _TheSameDocumentAlwaysEncodesTheSameWay is UnitTest
  fun name(): String => "a document always encodes the same way"

  fun apply(h: TestHelper) ? =>
    let once = SimHashFixture.encoder()?.encode("I came to the fork")?
    let twice = SimHashFixture.encoder()?.encode("I came to the fork")?

    h.assert_true(BoolArray.are_equal(once, twice))

class iso _CapitalsDoNotMatterUnlessAsked is UnitTest
  fun name(): String => "capitals are folded unless the caller wants them apart"

  fun apply(h: TestHelper) ? =>
    let folded = SimHashFixture.encoder()?
    h.assert_true(
      BoolArray.are_equal(folded.encode("The Sky")?, folded.encode("the sky")?),
      "one encoding for one document")

    let exact = SimHashFixture.encoder(400, 20, false, true)?
    h.assert_true(
      not BoolArray.are_equal(exact.encode("The Sky")?, exact.encode("the sky")?),
      "capitals make different words when asked to")

class iso _AnExcludedWordIsNotCounted is UnitTest
  fun name(): String => "an excluded word is not counted"

  fun apply(h: TestHelper) ? =>
    let words: Array[String] val = recover val
      ["but"; "it"; "all"; "stays"; "the"; "same"]
    end
    let noise: Array[String] val = recover val
      ["seasons"; "change"; "mad"; "things"; "rearrange"]
    end

    let document = _sentence(words, noise)
    let kept = _sentence(words, recover val Array[String] end)

    let plain = SimHashFixture.encoder()?
    h.assert_true(not BoolArray.are_equal(plain.encode(document)?, plain.encode(kept)?),
      "the extra words change the encoding")

    let ignoring = SimHashFixture.encoder(400, 20, false, false, 0, noise)?
    h.assert_true(BoolArray.are_equal(ignoring.encode(document)?, ignoring.encode(kept)?),
      "with the extra words ignored, the two documents are the same")

  fun _sentence(
    first: Array[String] val,
    second: Array[String] val)
    : String
  =>
    var sentence: String = ""
    for word in first.values() do
      sentence = sentence + word + " "
    end
    for word in second.values() do
      sentence = sentence + word + " "
    end
    sentence

class iso _AWordRepeatedManyTimesCountsUpToTheCeiling is UnitTest
  fun name(): String => "a repeated word counts no more than the ceiling"

  fun apply(h: TestHelper) ? =>
    let plain = SimHashFixture.encoder(400, 20)?
    let capped = SimHashFixture.encoder(400, 20, false, false, 2)?
    let repeated = "a a a b b c d d d d e e f"

    h.assert_true(not BoolArray.are_equal(plain.encode(repeated)?, capped.encode(repeated)?),
      "the words that repeat decide differently once they are capped")

class iso _LettersBringSimilarWordsTogether is UnitTest
  fun name(): String => "counting letters brings similar words together"

  fun apply(h: TestHelper) ? =>
    let words: Bool = true
    let letters: Bool = true

    let without = SimHashFixture.encoder(400, 20, not words)?
    let with_letters = SimHashFixture.encoder(400, 20, letters)?

    let near = SimHashFixture.overlap(
      without.encode("cat sat on the mat")?,
      without.encode("cats sat on the mat")?)
    let near_with_letters = SimHashFixture.overlap(
      with_letters.encode("cat sat on the mat")?,
      with_letters.encode("cats sat on the mat")?)

    h.log("shared positions without letters: " + near.string()
      + ", with: " + near_with_letters.string())
    h.assert_true(near_with_letters > near,
      "a plural is nearer when its letters are counted")

class iso _OneLetterChangesAlmostEveryBitOfADigest is UnitTest
  fun name(): String => "a one-letter change moves half the digest"

  fun apply(h: TestHelper) ? =>
    let before = TokenDigest.bits(TokenDigest.of("dog", 0, 3, false)?, 200)
    let after = TokenDigest.bits(TokenDigest.of("dogs", 0, 4, false)?, 200)

    var differ: USize = 0
    var index: USize = 0
    while index < 200 do
      if (try before(index)? else false end) !=
        (try after(index)? else false end)
      then
        differ = differ + 1
      end
      index = index + 1
    end

    h.log("positions that differ for one added letter: " + differ.string())
    h.assert_true((differ > 70) and (differ < 130),
      "roughly half of two hundred positions differ")
