use "pony_test"
use "../htm"
use "../htm/encoders"

class SDRCategoryEncoderTest is TestList
  fun name(): String => "Open-set category encoder"

  fun tag tests(test: PonyTest) =>
    test(_TheWidthDoesNotGrowWithTheLabels)
    test(_ACategoryIsAsWideAsItIsToldAndNoWider)
    test(_ARepeatedLabelKeepsItsPositions)
    test(_TwoLabelsHaveSomewhereToDiffer)
    test(_ALabelNobodyMetIsAddedRatherThanRefused)
    test(_TheUnknownCategoryIsThereFromTheStart)
    test(_TheSeedDecidesThePositions)

class iso _TheWidthDoesNotGrowWithTheLabels is UnitTest
  fun name(): String => "the width does not grow with the labels"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(100, 4)?

    let first = encoder.encode("a")
    h.assert_eq[USize](100, encoder.width())

    var met: USize = 0
    while met < 50 do
      encoder.encode("label " + met.string())
      met = met + 1
    end

    // fifty more categories, and the same width and the same number of bits
    h.assert_eq[USize](100, encoder.width())
    h.assert_eq[USize](4, first.size())

class iso _ACategoryIsAsWideAsItIsToldAndNoWider is UnitTest
  fun name(): String => "a category turns on the number of bits it was told, inside the width"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(64, 5)?
    let encoding = encoder.encode("a")

    h.assert_eq[USize](5, encoding.size())
    for position in encoding.values() do
      h.assert_true(position < 64, "a position inside the width")
    end

class iso _ARepeatedLabelKeepsItsPositions is UnitTest
  fun name(): String => "the same label always encodes the same way"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(64, 5)?

    h.assert_array_eq[USize](encoder.encode("a"), encoder.encode("a"))

class iso _TwoLabelsHaveSomewhereToDiffer is UnitTest
  fun name(): String => "two labels do not encode the same"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(100, 4)?
    let first = encoder.encode("a")
    let second = encoder.encode("b")

    var different = false
    for position in first.values() do
      if not second.contains(position) then different = true end
    end

    h.assert_true(different, "two categories may share bits, but not all of them")

class iso _ALabelNobodyMetIsAddedRatherThanRefused is UnitTest
  fun name(): String => "a label nobody met is added rather than refused"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(100, 4)?

    h.assert_false(encoder.knows("a"))
    let encoding = encoder.encode("a")

    h.assert_true(encoder.knows("a"))
    h.assert_eq[USize](1, encoder.labels())
    h.assert_eq[USize](4, encoding.size())

class iso _TheUnknownCategoryIsThereFromTheStart is UnitTest
  fun name(): String => "there is something to encode before any label is met"

  fun apply(h: TestHelper) ? =>
    let encoder = SDRCategoryEncoder(100, 4)?

    h.assert_eq[USize](0, encoder.labels())
    h.assert_eq[USize](4, encoder.unknown().size())

class iso _TheSeedDecidesThePositions is UnitTest
  fun name(): String => "the same seed and the same labels give the same encodings"

  fun apply(h: TestHelper) ? =>
    let one = SDRCategoryEncoder(100, 4, 7)?
    let other = SDRCategoryEncoder(100, 4, 7)?

    h.assert_array_eq[USize](one.encode("a"), other.encode("a"))
    h.assert_array_eq[USize](one.unknown(), other.unknown())
