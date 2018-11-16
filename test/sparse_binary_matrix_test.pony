use "ponytest"
use "../htm"

// https://github.com/htm-community/htm/blob/master/sparseBinaryMatrix_test.go

class SparseBinaryMatrixTest is TestList
  fun name(): String => "Sparse binary matrix"
  
  fun tag tests(test: PonyTest) =>
    test(_SparseGetSet)
    test(_SparseRowReplace)
    test(_SparseRowReplaceByIndices)

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

class iso _SparseRowReplace is UnitTest
  fun name(): String => "replacing a whole row"

  fun apply(h: TestHelper) =>
      let sm = SparseBinaryMatrix(10, 10)
    sm.set(2, 4, true)
    sm.set(6, 5, true)
    sm.set(7, 5, true)
    sm.set(8, 8, true)

    // before replacement
    h.assert_false(sm.get(8,6))
    h.assert_true(sm.get(8,8))

    // row dimension must match the matrix width
    h.assert_isnt[MatrixResult](SetOk, sm.replace_row(8,[false;false]))

    // if the dimension matches, replace the row
    let new_row: Array[Bool] = [false;false;false;false;false;false;true /*@6*/;false;false;false]
    h.assert_is[MatrixResult](SetOk, sm.replace_row(8, new_row))
    
    // after replacement
    h.assert_true(sm.get(8,6))
    h.assert_false(sm.get(8,8))


class iso _SparseRowReplaceByIndices is UnitTest
  fun name(): String => "replacing row items by indices"

  fun apply(h: TestHelper) =>
    let sm = SparseBinaryMatrix(10, 10)
    let indices: Array[USize] = [3; 9; 6]
    // the row entries with the indices
    //   included in the array will be set to true
    sm.replace_row_by_indices(4, indices)
    h.assert_true(sm.get(4,3))
    h.assert_true(sm.get(4,9))
    h.assert_true(sm.get(4,6))
    h.assert_false(sm.get(4,5))
    h.assert_false(sm.get(4,0))

    // running with other indices replaces the row values 
    sm.replace_row_by_indices(4, [4])
    h.assert_false(sm.get(4,3))
    h.assert_false(sm.get(4,9))
    h.assert_true(sm.get(4,4))

    // having out of range column indices in the list
    // resets the row to all false values, and doesn't fail
    h.assert_is[MatrixResult](SetOk, sm.replace_row_by_indices(5, [0; 9]))
    h.assert_true(sm.get(5,0))
    h.assert_true(sm.get(5,9))
    h.assert_is[MatrixResult](SetOk, sm.replace_row_by_indices(5, [99; 100]))
    h.assert_false(sm.get(5,0))
    h.assert_false(sm.get(5,9))

    // out-of-range row is a failure to insert
    h.assert_true(sm.replace_row_by_indices(99, [0; 1]) is SetFailed)
