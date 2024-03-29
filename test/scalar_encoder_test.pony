use "pony_test"
use "../htm/encoders"
use "../htm/util"
use "debug"

// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder_test.go

class ScalarEncoderTest is TestList
  fun name(): String => "Scalar encoder"
  
  fun tag tests(test: PonyTest) =>
    test(_TestSimpleEncoding)
    test(_TestWideEncoding)
    test(_TestNarrowEncoding)
    test(_TestSimpleDecoding)

class iso _TestSimpleEncoding is UnitTest
  fun name(): String => "scalar encoding: basics"

  fun apply(h: TestHelper) ? =>
    let p = ScalarEncoderParams(3, 1, 8 where
      n' = 14,
      periodic' = true
    )
    let e = ScalarEncoder(p) ?

    var encoded = e.encode(1, false) as Array[Bool]
    h.assert_array_eq[Bool](
      BoolArray.from01([1;1;0;0;0;0;0;0;0;0;0;0;0;1]),
      encoded
    )

    encoded = e.encode(2, false) as Array[Bool]
    h.assert_array_eq[Bool](
      BoolArray.from01([0;1;1;1;0;0;0;0;0;0;0;0;0;0]),
      encoded
    )

    encoded = e.encode(3, false) as Array[Bool]
    h.assert_array_eq[Bool](
      BoolArray.from01([0;0;0;1;1;1;0;0;0;0;0;0;0;0]),
      encoded
    )

class iso _TestWideEncoding is UnitTest
  fun name(): String => "scalar encoding: larger vectors"

  fun apply(h: TestHelper) ? =>
    let p = ScalarEncoderParams(5, 0, 24 where
      radius' = 4,
      periodic' = true
    )
    let e = ScalarEncoder(p) ?

    var encoded = e.encode(14.916666666666666, false) as Array[Bool]
    h.assert_array_eq[Bool](
      BoolArray.from01([0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;1;1;1;1;0;0;0;0;0;0;0;0;0]),
      encoded
    )

    h.assert_eq[USize](encoded.size(), 30)


class iso _TestNarrowEncoding is UnitTest
  fun name(): String => "scalar encoding: smaller vectors"

  fun apply(h: TestHelper) ? =>
    let p = ScalarEncoderParams(3, 0, 1 where
      radius' = 1,
      periodic' = false
    )
    let e = ScalarEncoder(p) ?

    var encoded = e.encode(0, false) as Array[Bool]
    h.assert_array_eq[Bool](
      BoolArray.from01([1;1;1;0;0;0]),
      encoded
    )
    h.assert_eq[USize](encoded.size(), 6)


class iso _TestSimpleDecoding is UnitTest
  fun name(): String => "decoding scalars"

  fun apply(h: TestHelper) ? =>
    let p = ScalarEncoderParams(3, 1, 8 where
      radius' = 1.5,
      periodic' = true
    )
    let e = ScalarEncoder(p) ?

    // Test with a "hole"
    var encoded = BoolArray.from01([1;0;0;0;0;0;0;0;0;0;0;0;1;0])
    var decoded = e.decode(encoded) ?
    h.assert_array_eq[ScalarRange](
      decoded,
      [ScalarRange(7.5, 7.5)]
    )

    // Test with something wider than w, and with a hole, and wrapped
    encoded = BoolArray.from01([1;1;0;0;0;0;0;0;0;0;0;0;1;0])
    decoded = e.decode(encoded) ?
    h.assert_array_eq[ScalarRange](
      decoded,
      [ScalarRange(7.5, 8); ScalarRange(1, 1)]
    )

    // Test with something wider than w, no hole
    encoded = BoolArray.from01([1;1;1;1;1;0;0;0;0;0;0;0;0;0])
    decoded = e.decode(encoded) ?
    h.assert_array_eq[ScalarRange](
      decoded,
      [ScalarRange(1.5, 2.5)]
    )

    // 1
    encoded = BoolArray.from01([1;1;0;0;0;0;0;0;0;0;0;0;0;1])
    decoded = e.decode(encoded) ?
    h.assert_array_eq[ScalarRange](
      decoded,
      [ScalarRange(1, 1)]
    )

    // 2
    encoded = BoolArray.from01([0;1;1;1;0;0;0;0;0;0;0;0;0;0])
    decoded = e.decode(encoded) ?
    h.assert_array_eq[ScalarRange](
      decoded,
      [ScalarRange(2, 2)]
    )
