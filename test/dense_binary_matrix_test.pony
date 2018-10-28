use "ponytest"
use "../htm"

// https://github.com/htm-community/htm/blob/master/denseBinaryMatrix_test.go

class DenseBinaryMatrixTest is TestList
  fun name(): String => "Dense binary matrix"
  
  fun tag tests(test: PonyTest) =>
    test(_DenseGetSet)

class iso _DenseGetSet is UnitTest
  fun name(): String => "setting and getting values"

  fun apply(h: TestHelper) =>
    let sm = DenseBinaryMatrix(10, 10)

    // setting a value within range
	h.assert_true(sm.set(2, 4, true) is SetOk)

    // setting a value outside the range is an error
    h.assert_false(sm.set(10, 10, true) is SetOk)

	sm.set(6, 5, true)
	sm.set(7, 5, false)

    // the out of range result is simply false
    h.assert_false(sm.get(11,12))

    // the value not yet set is false
    h.assert_false(sm.get(1,1))

    // the set values should be as expected
    h.assert_true(sm.get(2,4))
    h.assert_true(sm.get(6,5))
    h.assert_false(sm.get(7,5))
