use "pony_test"
use "../htm"

// The Go reference: spatialPooler.calculateOverlap, over connected synapses;
// raisePermanenceToThreshold; and adaptSynapses, whose numbers the learning test
// below reproduces.

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
    test(_ARoundOfLearningMovesEachBeliefOneStep)
    test(_AColumnIsRaisedUntilItCanBeHeard)

primitive Beliefs
  """
  Reading permanences back. A learning step is floating-point arithmetic, so the
  numbers are compared to a tolerance rather than for equality.
  """
  fun near(h: TestHelper, expect: F64, actual: F64) =>
    h.assert_true((expect - actual).abs() < 0.000000001,
      "expected " + expect.string() + ", got " + actual.string())

  fun column(h: TestHelper, expect: ReadSeq[F64], actual: ReadSeq[F64]) =>
    h.assert_eq[USize](expect.size(), actual.size(), "the same number of synapses")
    try
      var index: USize = 0
      while index < expect.size() do
        near(h, expect(index)?, actual(index)?)
        index = index + 1
      end
    end

  fun of(held: Column): Array[F64] =>
    let values = Array[F64]
    for synapse in held.synapses.values() do
      values.push(synapse.permanence)
    end
    values

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

class iso _ARoundOfLearningMovesEachBeliefOneStep is UnitTest
  fun name(): String => "a round of learning moves each belief by one step"

  fun apply(h: TestHelper) =>
    // the reference's adaptSynapses: one input, three winning columns, one round
    // of a tenth of a step up, a hundredth down, and everything under 0.05 let go
    let input: Array[Bool] val = recover val
      [true; false; false; true; true; false; true; false]
    end

    let saw_it = Column([Synapse(0, 0.200); Synapse(1, 0.120); Synapse(2, 0.090); Synapse(3, 0.040)])
    let partly = Column([Synapse(0, 0.150); Synapse(4, 0.180); Synapse(5, 0.120); Synapse(7, 0.450)])
    let mistook = Column([Synapse(2, 0.014); Synapse(6, 0.110)])

    for column in [saw_it; partly; mistook].values() do
      column.adapt(input, 0.1, 0.01)
      column.trim(0.05)
    end

    Beliefs.column(h, [0.300; 0.110; 0.080; 0.140], Beliefs.of(saw_it))
    Beliefs.column(h, [0.250; 0.280; 0.110; 0.440], Beliefs.of(partly))

    // the weak belief moved down by a hundredth and was then let go of
    Beliefs.column(h, [0.000; 0.210], Beliefs.of(mistook))

class iso _AColumnIsRaisedUntilItCanBeHeard is UnitTest
  fun name(): String => "a column is raised until enough of it is connected"

  fun apply(h: TestHelper) =>
    // the reference's raisePermanenceToThreshold: three connected synapses make
    // a column heard, and the whole receptive field moves one stride together
    let shy = Column([Synapse(0, 0.0); Synapse(1, 0.11); Synapse(2, 0.095); Synapse(3, 0.092); Synapse(4, 0.01)])
    let heard = Column([Synapse(0, 0.12); Synapse(1, 0.15); Synapse(2, 0.02); Synapse(3, 0.12); Synapse(4, 0.09)])
    let nearly = Column([Synapse(0, 0.51); Synapse(1, 0.081); Synapse(2, 0.025); Synapse(3, 0.089); Synapse(4, 0.31)])
    let awkward = Column([Synapse(0, 0.18); Synapse(1, 0.0601); Synapse(2, 0.11); Synapse(3, 0.011); Synapse(4, 0.03)])
    let silent = Column([Synapse(0, 0.011); Synapse(1, 0.011); Synapse(2, 0.011); Synapse(3, 0.011); Synapse(4, 0.011)])

    for column in [shy; heard; nearly; awkward; silent].values() do
      column.ensure_connected(3, 0.1, 0.01)
    end

    // one stride, because a single raise makes three of them connected
    Beliefs.column(h, [0.01; 0.12; 0.105; 0.102; 0.02], Beliefs.of(shy))

    // already heard: left exactly as it was
    Beliefs.column(h, [0.12; 0.15; 0.02; 0.12; 0.09], Beliefs.of(heard))

    // two strides, and only then four synapses are connected
    Beliefs.column(h, [0.53; 0.101; 0.045; 0.109; 0.33], Beliefs.of(nearly))

    // four strides, the last of which tips 0.0601 over the threshold
    Beliefs.column(h, [0.22; 0.1001; 0.15; 0.051; 0.07], Beliefs.of(awkward))

    // nine strides, until the whole receptive field is connected
    Beliefs.column(h, [0.101; 0.101; 0.101; 0.101; 0.101], Beliefs.of(silent))
