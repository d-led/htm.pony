use "ponytest"
use "../htm/encoders"

// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder_test.go

class ScalarEncoderTest is TestList
  fun name(): String => "Scalar encoder"
  
  fun tag tests(test: PonyTest) =>
    test(_TestSimpleEncoding)

class iso _TestSimpleEncoding is UnitTest
  fun name(): String => "scalar encoding basics"

  fun apply(h: TestHelper) ? =>
    let p = ScalarEncoderParams(3, 1, 8 where
      n' = 14,
      periodic' = true
    )

    let e = ScalarEncoder(p) ?
    // let encoded = e.encode(1, false)?
