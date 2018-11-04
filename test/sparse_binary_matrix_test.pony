use "ponytest"
use "../htm"

// https://github.com/htm-community/htm/blob/master/sparseBinaryMatrix_test.go

class SparseBinaryMatrixTest is TestList
  fun name(): String => "Sparse binary matrix"
  
  fun tag tests(test: PonyTest) =>
    test(_SparseGetSet)

class iso _SparseGetSet is UnitTest
  fun name(): String => "sparse matrix: setting and getting values"

  fun apply(h: TestHelper) =>
    let sm = SparseBinaryMatrix(10, 10)

    // setting a value within range
	  h.assert_is[MatrixResult](SetOk, sm.set(2, 4, true))

    // setting a value outside the range is an error
    h.assert_isnt[MatrixResult](SetOk, sm.set(10, 10, true))

    sm.set(6, 5, true)

    sm.set(7, 5, true)
    sm.set(7, 5, false)

    // the out of range result is simply false
    h.assert_false(sm.get(11,12))

    // the value not yet set is false
    h.assert_false(sm.get(1,1))

    h.assert_true(sm.get(2,4))
    h.assert_true(sm.get(6,5))
    h.assert_false(sm.get(7,5))
