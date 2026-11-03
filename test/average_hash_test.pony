use "pony_test"

use "../htm/encoders"
use "../htm/measure"

class AverageHashTest is TestList
  fun name(): String => "The average hash"
  fun tag tests(test: PonyTest) =>
    test(_TheSamePictureAtTwiceTheSizeGivesTheSameFingerprint)
    test(_ABrighterCopyGivesTheSameFingerprint)
    test(_HalfTheBitsAreSet)
    test(_TwoDifferentPicturesShareFewBits)
    test(_TheMedianOfAnOddCountIsTheMiddleValue)
    test(_TheMedianOfAnEvenCountIsBetweenTheTwoMiddles)

class iso _TheSamePictureAtTwiceTheSizeGivesTheSameFingerprint is UnitTest
  fun name(): String => "average hash: a picture twice as wide has the same layout"
  fun apply(h: TestHelper) ? =>
    let picture = Synthetic.pattern(64, 64)?
    let twice = Distortions.scaled(picture, 2)?
    let before = AverageHash.compute(picture)?
    let after = AverageHash.compute(twice)?
    h.assert_eq[USize](0, before.hamming(after)?)

class iso _ABrighterCopyGivesTheSameFingerprint is UnitTest
  fun name(): String => "average hash: a brighter copy lays out the same"
  fun apply(h: TestHelper) ? =>
    let picture = Synthetic.pattern(64, 64)?
    let brighter = Distortions.brighter(picture, 40)?
    let before = AverageHash.compute(picture)?
    let after = AverageHash.compute(brighter)?
    h.assert_eq[USize](0, before.hamming(after)?)

class iso _HalfTheBitsAreSet is UnitTest
  fun name(): String => "average hash: no more than half the bits are set"
  fun apply(h: TestHelper) ? =>
    let fingerprint = AverageHash.compute(Synthetic.ring(64, 64)?)?
    h.assert_true(fingerprint.active() > 64)
    h.assert_true(fingerprint.active() <= 128)

class iso _TwoDifferentPicturesShareFewBits is UnitTest
  fun name(): String => "average hash: two different pictures share few bits"
  fun apply(h: TestHelper) ? =>
    let ramp = AverageHash.compute(Synthetic.pattern(64, 64)?)?
    let bars = AverageHash.compute(Synthetic.stripes(64, 64)?)?
    h.assert_true(ramp.hamming(bars)? > 64)

class iso _TheMedianOfAnOddCountIsTheMiddleValue is UnitTest
  fun name(): String => "median: an odd count has a middle value"
  fun apply(h: TestHelper) ? =>
    let values: Array[F64] = [3.0; 1.0; 2.0]
    h.assert_eq[F64](2.0, Median.of(values)?)

class iso _TheMedianOfAnEvenCountIsBetweenTheTwoMiddles is UnitTest
  fun name(): String => "median: an even count sits between the two middles"
  fun apply(h: TestHelper) ? =>
    let values: Array[F64] = [4.0; 2.0; 1.0; 3.0]
    h.assert_eq[F64](2.5, Median.of(values)?)
