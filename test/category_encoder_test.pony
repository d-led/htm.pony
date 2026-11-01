use "pony_test"
use "../htm/encoders"

// The reference: nupic's encoders/category.py, which encodes category i as the
// i-th block of w bits. The one difference is stated in the encoder: an unknown
// category is refused here and encoded as <UNKNOWN> there.

class CategoryEncoderTest is TestList
  fun name(): String => "Category encoder"

  fun tag tests(test: PonyTest) =>
    test(_ACategoryOwnsItsOwnBlock)
    test(_TwoCategoriesShareNothing)
    test(_TheSameCategoryAlwaysEncodesAlike)
    test(_ACategoryItDoesNotHaveIsRefused)
    test(_AnEncodingIsReadBackAsItsCategory)
    test(_TwoCategoriesOfTheSameNameAreRefused)

primitive Categories
  fun names(): Array[String] val =>
    recover val ["north"; "south"; "east"; "west"] end

  fun encoder(bits: USize = 3): CategoryEncoder ? =>
    CategoryEncoder(names(), bits)?

  fun bits_set(encoded: ReadSeq[Bool]): Array[USize] =>
    let set = Array[USize]
    var index: USize = 0
    while index < encoded.size() do
      try
        if encoded(index)? then set.push(index) end
      end
      index = index + 1
    end
    set

class iso _ACategoryOwnsItsOwnBlock is UnitTest
  fun name(): String => "a category owns a block of its own in the encoding"

  fun apply(h: TestHelper) ? =>
    let encoder = Categories.encoder()?

    h.assert_eq[USize](12, encoder.width(), "four categories, three bits each")

    match encoder.encode("east")
    | let encoded: Array[Bool] =>
      // "east" is the third category, so its block starts at six
      h.assert_array_eq[USize]([6; 7; 8], Categories.bits_set(encoded))
    else
      h.fail("a known category should encode")
    end

class iso _TwoCategoriesShareNothing is UnitTest
  fun name(): String => "two categories have nothing in common"

  fun apply(h: TestHelper) ? =>
    let encoder = Categories.encoder()?

    match (encoder.encode("north"), encoder.encode("west"))
    | (let north: Array[Bool], let west: Array[Bool]) =>
      var shared: USize = 0
      var index: USize = 0
      while index < north.size() do
        if north(index)? and west(index)? then shared = shared + 1 end
        index = index + 1
      end
      h.assert_eq[USize](0, shared, "categories are not neighbours")
    else
      h.fail("both categories should encode")
    end

class iso _TheSameCategoryAlwaysEncodesAlike is UnitTest
  fun name(): String => "the same category always encodes the same way"

  fun apply(h: TestHelper) ? =>
    let encoder = Categories.encoder()?

    match (encoder.encode("south"), encoder.encode("south"))
    | (let first: Array[Bool], let second: Array[Bool]) =>
      h.assert_array_eq[Bool](first, second)
    else
      h.fail("a known category should encode")
    end

class iso _ACategoryItDoesNotHaveIsRefused is UnitTest
  fun name(): String => "a category it does not have is refused"

  fun apply(h: TestHelper) ? =>
    let encoder = Categories.encoder()?

    match encoder.encode("up")
    | EncodingFailed => h.complete(true)
    else
      h.fail("an unknown category should not be encoded as a real one")
    end

class iso _AnEncodingIsReadBackAsItsCategory is UnitTest
  fun name(): String => "an encoding is read back as the category it came from"

  fun apply(h: TestHelper) ? =>
    let encoder = Categories.encoder()?

    for known in Categories.names().values() do
      match encoder.encode(known)
      | let encoded: Array[Bool] =>
        match encoder.decode(encoded)
        | let back: String =>
          h.assert_eq[String](known, back, known + " should read back as itself")
        else
          h.fail(known + " should decode")
        end
      else
        h.fail(known + " should encode")
      end
    end

class iso _TwoCategoriesOfTheSameNameAreRefused is UnitTest
  fun name(): String => "two categories of the same name are refused"

  fun apply(h: TestHelper) =>
    let doubled: Array[String] val = recover val ["north"; "south"; "north"] end

    h.assert_error({() ? => CategoryEncoder(doubled)? })
