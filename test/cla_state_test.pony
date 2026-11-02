use "pony_test"
use "../htm"

// The Go reference: temporalPooler's DynamicState, and the copying the two
// phases do to and from it.

class ClaStateTest is TestList
  fun name(): String => "CLA cell state"

  fun tag tests(test: PonyTest) =>
    test(_ACellStartsInNoState)
    test(_AdvancingKeepsTheStepBefore)
    test(_ACellOutsideThePopulationIsIgnored)
    test(_TheCellsOfANodeAreFound)
    test(_CountingIsOverTheWholePopulation)
    test(_ACopyCarriesTheStepAndIsNotShared)
    test(_CreditLandsOnTheCellAndOnItsNode)
    test(_SharesAreOfTheWhole)
    test(_NothingToShareLeavesTheEstimateAlone)

class iso _ACellStartsInNoState is UnitTest
  fun name(): String => "no cell is active or predicted before the first step"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)

    h.assert_false(state.active(0))
    h.assert_false(state.predicted(0))
    h.assert_eq[USize](0, state.count_active())
    h.assert_eq[USize](0, state.count_predicted())

class iso _AdvancingKeepsTheStepBefore is UnitTest
  fun name(): String => "advancing keeps what was true as the step before"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)
    state.activate(5)
    state.predict(6)

    state.advance()
    state.clear_active()
    state.clear_predicted()

    h.assert_true(state.was_active(5))
    h.assert_true(state.was_predicted(6))
    h.assert_false(state.active(5))
    h.assert_false(state.predicted(6))

class iso _ACellOutsideThePopulationIsIgnored is UnitTest
  fun name(): String => "a cell outside the population is left out, not raised on"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)
    state.activate(12)
    state.predict(999)

    h.assert_false(state.active(12))
    h.assert_false(state.predicted(999))

class iso _TheCellsOfANodeAreFound is UnitTest
  fun name(): String => "the cells of one node are found by their position in it"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)
    state.activate(4)
    state.activate(7)
    state.predict(1)

    h.assert_array_eq[USize]([0; 3], state.active_in(1))
    h.assert_array_eq[USize]([1], state.predicted_in(0))
    h.assert_array_eq[USize](Array[USize], state.active_in(2))

class iso _CountingIsOverTheWholePopulation is UnitTest
  fun name(): String => "counting is over the whole population"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)
    state.activate(0)
    state.activate(5)
    state.activate(11)
    state.predict(2)

    h.assert_eq[USize](3, state.count_active())
    h.assert_eq[USize](1, state.count_predicted())

class iso _ACopyCarriesTheStepAndIsNotShared is UnitTest
  fun name(): String => "a copy carries the step without sharing it"

  fun apply(h: TestHelper) =>
    let state = CellState(3, 4)
    state.activate(1)
    state.predict(2)

    let carried = state.copy()
    state.activate(3)

    h.assert_true(carried.active(1))
    h.assert_true(carried.predicted(2))
    h.assert_false(carried.active(3))

class iso _CreditLandsOnTheCellAndOnItsNode is UnitTest
  fun name(): String => "a cell's confidence is also its node's"

  fun apply(h: TestHelper) =>
    let confidence = CellConfidence(3, 4)
    confidence.credit(5, 2.0)

    h.assert_eq[F64](2.0, confidence.cell_confidence(5))
    h.assert_eq[F64](2.0, confidence.node_confidence(1))
    h.assert_eq[F64](2.0, confidence.total())

    confidence.advance()
    confidence.clear()

    h.assert_eq[F64](2.0, confidence.cell_confidence_before(5))
    h.assert_eq[F64](0.0, confidence.cell_confidence(5))

class iso _SharesAreOfTheWhole is UnitTest
  fun name(): String => "confidences are shown as shares of everything the pooler is sure of"

  fun apply(h: TestHelper) =>
    let confidence = CellConfidence(3, 4)
    confidence.credit(0, 1.0)
    confidence.credit(5, 3.0)

    confidence.share_out()

    h.assert_eq[F64](0.25, confidence.cell_confidence(0))
    h.assert_eq[F64](0.75, confidence.cell_confidence(5))
    h.assert_eq[F64](0.75, confidence.node_confidence(1))
    h.assert_eq[F64](1.0, confidence.total())

class iso _NothingToShareLeavesTheEstimateAlone is UnitTest
  fun name(): String => "a pooler that is sure of nothing does not divide by nothing"

  fun apply(h: TestHelper) =>
    let confidence = CellConfidence(3, 4)

    confidence.share_out()

    h.assert_eq[F64](0.0, confidence.cell_confidence(0))
    h.assert_eq[F64](0.0, confidence.total())
