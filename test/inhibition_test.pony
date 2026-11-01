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
    test(_StrongestInItsNeighbourhoodWins)
    test(_AStrongerNeighbourTakesThePlace)
    test(_ADistantPeakIsRepresentedToo)
    test(_ALoneColumnAlwaysWins)
    test(_SparseAllowanceSilencesEdgeColumns)
    test(_AColumnThatMatchesNothingCannotWin)

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

class iso _StrongestInItsNeighbourhoodWins is UnitTest
  fun name(): String => "the column that beats its own neighbours wins"

  fun apply(h: TestHelper) ? =>
    let grid = Grid([3])?
    h.assert_array_eq[USize]([1], Inhibition.local([0.1; 0.9; 0.2], grid, 1, 0.2)?)

class iso _AStrongerNeighbourTakesThePlace is UnitTest
  fun name(): String => "a column with a stronger neighbour stays silent"

  fun apply(h: TestHelper) ? =>
    let grid = Grid([2])?
    h.assert_array_eq[USize]([1], Inhibition.local([0.2; 0.8], grid, 1, 0.3)?)

class iso _ADistantPeakIsRepresentedToo is UnitTest
  fun name(): String => "two separate peaks are both represented"

  fun apply(h: TestHelper) ? =>
    let grid = Grid([5])?
    h.assert_array_eq[USize]([0; 2; 4], Inhibition.local([0.9; 0.1; 0.8; 0.1; 0.7], grid, 1, 0.5)?)

class iso _SparseAllowanceSilencesEdgeColumns is UnitTest
  fun name(): String => "a low density can leave a column with too few neighbours to win"

  fun apply(h: TestHelper) ? =>
    // with one neighbour the allowance truncates to zero, so neither column wins
    let grid = Grid([2])?
    h.assert_eq[USize](0, Inhibition.local([0.9; 0.1], grid, 1, 0.2)?.size())

class iso _AColumnThatMatchesNothingCannotWin is UnitTest
  fun name(): String => "a column that matches no input cannot represent it"

  fun apply(h: TestHelper) ? =>
    let grid = Grid([4])?
    h.assert_eq[USize](0, Inhibition.winners([0.0; 0.0; 0.0], 2)?.size())
    h.assert_eq[USize](0, Inhibition.local([0.0; 0.0; 0.0; 0.0], grid, 1, 0.5)?.size())

class iso _ALoneColumnAlwaysWins is UnitTest
  fun name(): String => "a column with no neighbours always represents its area"

  fun apply(h: TestHelper) ? =>
    let grid = Grid([1])?
    h.assert_array_eq[USize]([0], Inhibition.local([0.4], grid, 1, 0.5)?)
