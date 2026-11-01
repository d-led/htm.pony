use "pony_test"
use "../htm"

// The Go reference: spatialPooler.inhibitColumnsGlobal.

class InhibitionTest is TestList
  fun name(): String => "Inhibition"

  fun tag tests(test: PonyTest) =>
    test(_StrongestColumnWins)
    test(_OnlyTheAllowedNumberOfColumnsSurvive)
    test(_WinnersComeBackInColumnOrder)
    test(_ATieGoesToTheEarlierColumn)
    test(_AskingForMoreWinnersThanColumns)
    test(_NoWinnersWhenNoneAreAllowed)

class iso _StrongestColumnWins is UnitTest
  fun name(): String => "the column that best matches the input represents it"

  fun apply(h: TestHelper) ? =>
    h.assert_array_eq[USize]([1], Inhibition.winners([0.1; 0.9; 0.5], 1)?)

class iso _OnlyTheAllowedNumberOfColumnsSurvive is UnitTest
  fun name(): String => "inhibition keeps only as many columns as the density allows"

  fun apply(h: TestHelper) ? =>
    let winners = Inhibition.winners([0.1; 0.9; 0.5; 0.7; 0.3], 2)?
    h.assert_eq[USize](2, winners.size())
    h.assert_array_eq[USize]([1; 3], winners)

class iso _WinnersComeBackInColumnOrder is UnitTest
  fun name(): String => "winners are reported in column order, not in the order they won"

  fun apply(h: TestHelper) ? =>
    // the strongest columns are 3, then 1, then 0 - the answer must not say so
    h.assert_array_eq[USize]([0; 1; 3], Inhibition.winners([0.6; 0.8; 0.2; 0.9], 3)?)

class iso _ATieGoesToTheEarlierColumn is UnitTest
  fun name(): String => "an exact tie is settled in favour of the earlier column"

  fun apply(h: TestHelper) ? =>
    h.assert_array_eq[USize]([0], Inhibition.winners([0.5; 0.5], 1)?)

class iso _AskingForMoreWinnersThanColumns is UnitTest
  fun name(): String => "asking for more winners than there are columns returns them all"

  fun apply(h: TestHelper) ? =>
    h.assert_array_eq[USize]([0; 1; 2], Inhibition.winners([0.2; 0.1; 0.3], 5)?)

class iso _NoWinnersWhenNoneAreAllowed is UnitTest
  fun name(): String => "nothing wins when the density allows no column to"

  fun apply(h: TestHelper) ? =>
    h.assert_eq[USize](0, Inhibition.winners([0.9; 0.8], 0)?.size())
