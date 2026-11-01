use "pony_test"
use "../htm/encoders"

// The reference: nupic's encoders/random_distributed_scalar.py. Its rules are
// kept; its bits are not, because they come from this library's generator. What
// the tests hold it to is the property the encoder exists for: near values
// overlap, far values do not.

class RandomDistributedScalarTest is TestList
  fun name(): String => "Random distributed encoder"

  fun tag tests(test: PonyTest) =>
    test(_TheEncodingIsAsWideAsItsWidth)
    test(_TheSameValueAlwaysEncodesAlike)
    test(_ValuesWithinOneResolutionAreTheSame)
    test(_NeighboursDifferInOneBit)
    test(_TwoBucketsApartDifferInTwoBits)
    test(_ValuesFarApartShareAlmostNothing)
    test(_AnotherSeedGivesOtherBits)

primitive Distributed
  fun encoder(seed: U64 = 42): RandomDistributedScalarEncoder ? =>
    RandomDistributedScalarEncoder(0.1, 21, 400, seed)?

  fun encoding(of: RandomDistributedScalarEncoder, value: F64): Array[Bool] val ? =>
    let bits: Array[Bool] iso = of.encode(value)?
    consume bits

  fun shared(left: ReadSeq[Bool], right: ReadSeq[Bool]): USize =>
    var count: USize = 0
    var index: USize = 0
    while index < left.size() do
      try
        if left(index)? and right(index)? then count = count + 1 end
      end
      index = index + 1
    end
    count

  fun set_bits(encoded: ReadSeq[Bool]): USize =>
    var count: USize = 0
    for one in encoded.values() do
      if one then count = count + 1 end
    end
    count

class iso _TheEncodingIsAsWideAsItsWidth is UnitTest
  fun name(): String => "the encoding is as wide as the encoder, with its share of bits"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?
    let encoded = Distributed.encoding(encoder, 1.0)?

    h.assert_eq[USize](400, encoded.size())
    h.assert_eq[USize](21, Distributed.set_bits(encoded))

class iso _TheSameValueAlwaysEncodesAlike is UnitTest
  fun name(): String => "the same value always encodes the same way"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?

    h.assert_array_eq[Bool](
      Distributed.encoding(encoder, 1.0)?, Distributed.encoding(encoder, 1.0)?)

class iso _ValuesWithinOneResolutionAreTheSame is UnitTest
  fun name(): String => "values within one resolution are the same value"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?

    h.assert_array_eq[Bool](
      Distributed.encoding(encoder, 1.0)?, Distributed.encoding(encoder, 1.02)?,
      "a fortieth of a bucket is still the same bucket")

class iso _NeighboursDifferInOneBit is UnitTest
  fun name(): String => "neighbouring buckets differ in exactly one bit"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?

    let here = Distributed.encoding(encoder, 1.0)?
    let next = Distributed.encoding(encoder, 1.1)?

    h.assert_eq[USize](20, Distributed.shared(here, next),
      "twenty of twenty-one bits should be kept")

class iso _TwoBucketsApartDifferInTwoBits is UnitTest
  fun name(): String => "buckets two apart differ in exactly two bits"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?

    let here = Distributed.encoding(encoder, 1.0)?
    let beyond = Distributed.encoding(encoder, 1.2)?

    h.assert_eq[USize](19, Distributed.shared(here, beyond))

class iso _ValuesFarApartShareAlmostNothing is UnitTest
  fun name(): String => "values far apart share almost nothing"

  fun apply(h: TestHelper) ? =>
    let encoder = Distributed.encoder()?

    // twenty-one buckets apart is a whole representation's width
    let here = Distributed.encoding(encoder, 1.0)?
    let far = Distributed.encoding(encoder, 3.1)?

    h.assert_true(Distributed.shared(here, far) <= 2,
      "distant values should share at most two bits")

class iso _AnotherSeedGivesOtherBits is UnitTest
  fun name(): String => "another seed gives another set of bits"

  fun apply(h: TestHelper) ? =>
    let first = Distributed.encoder(7)?
    let second = Distributed.encoder(8)?

    let one = Distributed.encoding(first, 1.0)?
    let other = Distributed.encoding(second, 1.0)?

    h.assert_true(Distributed.shared(one, other) < 21,
      "two encoders are not meant to agree bit for bit")
