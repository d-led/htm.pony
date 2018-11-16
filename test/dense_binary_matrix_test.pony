use "ponytest"
use "../htm"

// https://github.com/htm-community/htm/blob/master/denseBinaryMatrix_test.go

class DenseBinaryMatrixTest is TestList
  fun name(): String => "Dense binary matrix"
  
  fun tag tests(test: PonyTest) =>
    test(_DenseGetSet)
    test(_DenseRowReplace)
    test(_DenseRowReplaceByIndices)
    test(_DenseGetRowIndices)
    test(_DenseGetRowAndSum)
    test(_DenseNewFromDense)

class iso _DenseGetSet is UnitTest
  fun name(): String => "dense matrix: setting and getting values"

  fun apply(h: TestHelper) =>
    let sm = DenseBinaryMatrix(10, 10)

    // setting a value within range
	h.assert_is[MatrixResult](SetOk, sm.set(2, 4, true))

    // setting a value outside the range is an error
    h.assert_isnt[MatrixResult](SetOk, sm.set(10, 10, true))

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

class iso _DenseRowReplace is UnitTest
    fun name(): String => "replacing a whole row"

    fun apply(h: TestHelper) =>
        let sm = DenseBinaryMatrix(10, 10)
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

class iso _DenseRowReplaceByIndices is UnitTest
    fun name(): String => "replacing row items by indices"

    fun apply(h: TestHelper) =>
        let sm = DenseBinaryMatrix(10, 10)
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

class iso _DenseGetRowIndices is UnitTest
    fun name(): String => "getting the 'on' indices in a row"

    fun apply(h: TestHelper) =>
        let sm = DenseBinaryMatrix(10, 10)
        sm.replace_row_by_indices(4, [3; 6; 9])

        let indices_on = sm.get_row_indices(4)

        h.assert_array_eq[USize]([3; 6; 9], indices_on)

        h.assert_array_eq[USize]([], sm.get_row_indices(42))

class iso _DenseGetRowAndSum is UnitTest
    fun name(): String => "getting specific sums of row values"

    fun apply(h: TestHelper) =>
        let sm = DenseBinaryMatrix(10, 10)

        sm.set_row_from_dense(0, [true; false; true; true; false])
        sm.set_row_from_dense(1, [false; false; false; true; false])
        sm.set_row_from_dense(2, [false; false; false; false; false])
        sm.set_row_from_dense(3, [true; true; true; true; true])

        let rows_to_sum = [true; false; true; true; false]
        let result = sm.row_and_sum(rows_to_sum)

        // result array has the dimension of the matrix height
        h.assert_array_eq[USize]([3; 1; 0; 3; /* 0s after last true input*/ 0;0;0;0;0;0], result)

class _DenseNewFromDense is UnitTest
    fun name(): String => "construction from a dense 2d array"

    fun apply(h: TestHelper) ? =>
        let sbm = DenseBinaryMatrix.from_dense_2d_array([
            [true; true; true]
            [false; false; false]
            [false; true; false]
            [true; false; true]       
        ])?

        h.assert_eq[USize](4, sbm.height)
        h.assert_eq[USize](3, sbm.width)
        h.assert_true(sbm.get(3,2))
