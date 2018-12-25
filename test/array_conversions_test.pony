use "ponytest"
use "../htm/util"

class ArrayConversionsTest is TestList
  fun name(): String => "bool vector conversions"

  fun tag tests(test: PonyTest) =>
    test(_FromIntegerArrayConversionTest)
    test(_BoolArrayEqualityTest)
    test(_BoolArraySlicesTest)
    test(_BoolArraySettingValuesTest)
    test(_BoolArrayQueriesTest)

class iso _FromIntegerArrayConversionTest is UnitTest
  fun name(): String => "test utility to define bool vectors concisely"

  fun apply(h: TestHelper) =>
    // empty
    h.assert_array_eq[Bool](
        BoolArray.from01([]),
        []
    )

    // non-empty
    h.assert_array_eq[Bool](
        BoolArray.from01([0;1;1;0;1;0]),
        [false;true;true;false;true;false]
    )


class iso _BoolArrayEqualityTest is UnitTest
  fun name(): String => "test bool arrays for equality"

  fun apply(h: TestHelper) =>
    h.assert_true(BoolArray.are_equal([],[]))
    h.assert_true(BoolArray.are_equal([true],[true]))
    h.assert_true(BoolArray.are_equal([true;false],[true;false]))
    h.assert_false(BoolArray.are_equal([true],[false]))
    h.assert_false(BoolArray.are_equal([true;false],[false;true]))
    h.assert_false(BoolArray.are_equal([true;true],[true;true;true]))
    h.assert_false(BoolArray.are_equal([true;true;true],[true;true]))

class iso _BoolArraySlicesTest is UnitTest
  fun name(): String => "test taking slices of bool arrays"

  fun apply(h: TestHelper) ? =>
    h.assert_array_eq[Bool](
        BoolArray.subset_slice([true;false;true;false], [0;2;3]) ?,
        [true;true;false]
    )

class iso _BoolArraySettingValuesTest is UnitTest
  fun name(): String => "test setting values of certain indices in bool arrays"

  fun apply(h: TestHelper) ? =>
    var arr = Array[Bool].init(true, 4)
    BoolArray.set_value_at_indices(arr, [1;3], false) ?
    h.assert_array_eq[Bool](
        arr,
        [true;false;true;false]
    )

    // continuing on the same array
    BoolArray.set_value_in_range(arr, false, 1, 3) ?
    h.assert_array_eq[Bool](
        arr,
        [true;false;false;false]
    )
    BoolArray.set_value_in_range(arr, true, 0, 3) ?
    h.assert_array_eq[Bool](
        arr,
        [true;true;true;false]
    )

class iso _BoolArrayQueriesTest is UnitTest
  fun name(): String => "test querying indices of values that are on"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[USize](
        BoolArray.on_indices([true;false;true;false]),
        [0;2]
    )

    h.assert_array_eq[USize](
        BoolArray.on_indices([]),
        []
    )

    h.assert_array_eq[USize](
        BoolArray.on_indices([false;false]),
        []
    )

    h.assert_array_eq[USize](
        BoolArray.on_indices([true;true]),
        [0;1]
    )