use "ponytest"
use "../htm/conversions"

class iso _ArrayConversionsTest is UnitTest
  fun name(): String => "test utility to write denser bool vectors"

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