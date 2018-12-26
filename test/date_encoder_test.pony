use "ponytest"
use "../htm/encoders"
use "../htm/util"
use "debug"

// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder_test.go

class DateEncodingTest is TestList
  fun name(): String => "Date encoder"
  
  fun tag tests(test: PonyTest) =>
    test(_TestSimpleDateEncoding)

class iso _TestSimpleDateEncoding is UnitTest
  fun name(): String => "Simple date encoder basics"

  fun apply(h: TestHelper) =>
    true
