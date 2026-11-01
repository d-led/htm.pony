use "pony_test"
use "../htm"

// The Go reference: spatialPooler.calculateOverlap, over connected synapses.

class ColumnTest is TestList
  fun name(): String => "Column"

  fun tag tests(test: PonyTest) =>
    test(_SilentColumnHasNoOverlap)
    test(_OverlapCountsTheActiveInputsItIsConnectedTo)
    test(_WeakSynapsesDoNotCount)
    test(_InactiveInputNeverCounts)
    test(_SynapseOutsideTheInputIsAWiringError)
    test(_AdaptStrengthensWhatWasOnAndWeakensWhatWasNot)
    test(_PermanencesNeverLeaveTheRange)
    test(_WhatIsTooWeakToMatterIsLetGo)
    test(_AColumnTooWeakToBeHeardIsRaised)
    test(_AColumnThatCanBeHeardIsLeftAlone)

primitive TestSynapses
  """
  A synapse strong enough to count, and one too weak to.
  """
  fun solid(input: USize): Synapse => Synapse(input, 0.5)
  fun weak(input: USize): Synapse => Synapse(input, 0.01)

  fun threshold(): F64 => 0.2

class iso _SilentColumnHasNoOverlap is UnitTest
  fun name(): String => "a column sees nothing when no input is active"

  fun apply(h: TestHelper) ? =>
    let column = Column([TestSynapses.solid(0); TestSynapses.solid(1)])
    h.assert_eq[USize](0, column.overlap([false; false], TestSynapses.threshold())?)

class iso _OverlapCountsTheActiveInputsItIsConnectedTo is UnitTest
  fun name(): String => "a column's overlap is the active inputs it is connected to"

  fun apply(h: TestHelper) ? =>
    let column = Column([TestSynapses.solid(0); TestSynapses.solid(1); TestSynapses.solid(2)])

    // three connections, two of their inputs on
    h.assert_eq[USize](2, column.overlap([true; false; true], TestSynapses.threshold())?)

class iso _WeakSynapsesDoNotCount is UnitTest
  fun name(): String => "a synapse below the connection threshold does not count"

  fun apply(h: TestHelper) ? =>
    let column = Column([TestSynapses.solid(0); TestSynapses.weak(1)])

    // the input is on, but the connection to it is too weak to claim it
    h.assert_eq[USize](1, column.overlap([true; true], TestSynapses.threshold())?)

class iso _InactiveInputNeverCounts is UnitTest
  fun name(): String => "an inactive input never counts, however strong the synapse"

  fun apply(h: TestHelper) ? =>
    let column = Column([TestSynapses.solid(0)])

    h.assert_eq[USize](0, column.overlap([false], TestSynapses.threshold())?)

class iso _SynapseOutsideTheInputIsAWiringError is UnitTest
  fun name(): String => "a synapse reaching outside the input is a wiring error"

  fun apply(h: TestHelper) =>
    let column = Column([TestSynapses.solid(0); TestSynapses.solid(5)])

    h.assert_error({() ? => column.overlap([true; true], TestSynapses.threshold())? })

class iso _AdaptStrengthensWhatWasOnAndWeakensWhatWasNot is UnitTest
  fun name(): String => "a column strengthens the inputs it saw and weakens the rest"

  fun apply(h: TestHelper) =>
    let column = Column([Synapse(0, 0.5); Synapse(1, 0.5); Synapse(2, 0.5)])

    column.adapt([true; false; true], 0.1, 0.01)

    h.assert_eq[F64](0.6, _permanence(column, 0))
    h.assert_eq[F64](0.49, _permanence(column, 1))
    h.assert_eq[F64](0.6, _permanence(column, 2))

  fun _permanence(column: Column, input: USize): F64 =>
    try column.synapses(input)?.permanence else -1.0 end

class iso _PermanencesNeverLeaveTheRange is UnitTest
  fun name(): String => "a permanence stays a belief between nought and one"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapse(0, 0.95); Synapse(1, 0.02)])

    var round: USize = 0
    while round < 10 do
      column.adapt([true; false], 0.1, 0.01)
      round = round + 1
    end

    h.assert_eq[F64](1.0, column.synapses(0)?.permanence)
    h.assert_eq[F64](0.0, column.synapses(1)?.permanence)

class iso _WhatIsTooWeakToMatterIsLetGo is UnitTest
  fun name(): String => "a connection too weak to matter is let go of"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapse(0, 0.04); Synapse(1, 0.5); Synapse(2, 0.06)])

    column.trim(0.05)

    h.assert_eq[F64](0.0, column.synapses(0)?.permanence)
    h.assert_eq[F64](0.5, column.synapses(1)?.permanence)
    h.assert_eq[F64](0.06, column.synapses(2)?.permanence)

class iso _AColumnTooWeakToBeHeardIsRaised is UnitTest
  fun name(): String => "a column too weak to be heard raises its connections"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapse(0, 0.02); Synapse(1, 0.03)])

    // one connected synapse is needed, a connection takes 0.2, each raise is 0.05
    column.ensure_connected(1, 0.2, 0.05)

    h.assert_true(column.synapses(0)?.permanence >= 0.2,
      "the column should be able to claim an input now")

class iso _AColumnThatCanBeHeardIsLeftAlone is UnitTest
  fun name(): String => "a column that can already be heard is not raised"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapse(0, 0.5); Synapse(1, 0.03)])

    column.ensure_connected(1, 0.2, 0.05)

    h.assert_eq[F64](0.5, column.synapses(0)?.permanence)
    h.assert_eq[F64](0.03, column.synapses(1)?.permanence)
