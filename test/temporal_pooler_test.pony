use "pony_test"
use "../htm"

// The Go reference: temporalPooler_test.go's TestLearnPredict, with its own
// parameters, and the steps NewTemporalPooler.Compute takes with pooling off.

class TemporalPoolerTest is TestList
  fun name(): String => "CLA temporal pooler"

  fun tag tests(test: PonyTest) =>
    test(_AFreshPoolerBurstsAndPredictsNothing)
    test(_AResetStartsOnTheStartCells)
    test(_ALearnedSequenceIsPredicted)
    test(_TheOutputIsWhatIsActiveOrPredicted)
    test(_LearningGrowsSegments)
    test(_AnUnusedSynapseAgesAway)

primitive Patterns
  """
  The reference's five patterns: ten consecutive columns each, out of fifty.
  """
  fun of(index: USize): Array[USize] =>
    let columns = Array[USize](10)
    let start = index * 10
    var column: USize = start
    while column < (start + 10) do
      columns.push(column)
      column = column + 1
    end
    columns

  fun pooler(): TemporalPooler ? =>
    """
    The reference's TestLearnPredict setup: fifty nodes, two cells each, ten
    synapses to a segment, and no pooling.
    """
    let config = TemporalPoolerConfig(
      50, 2,              // nodes, and cells in each
      8, 10, 10,          // activation threshold, min threshold, synapses wanted
      false,              // no pooling
      0.5, 0.5,           // initial and connection permanence
      0.1, 0.0, 1.0,      // permanence increment, decrement, ceiling
      0.0,                // no global decay
      1, 10,              // update window, pam length
      10, 5,              // the two backtrack windows
      100000,             // nothing is ever aged out
      32,                 // longest sequence worth naming
      0, 0)?              // no fixed-size limits
    TemporalPooler(config, 7)

  fun learn_sequences(subject: TemporalPooler, epochs: USize) ? =>
    var epoch: USize = 0
    while epoch < epochs do
      var index: USize = 0
      while index < 5 do
        subject.compute(of(index), true, false)?
        index = index + 1
      end
      subject.reset()
      epoch = epoch + 1
    end

class iso _AFreshPoolerBurstsAndPredictsNothing is UnitTest
  fun name(): String => "a pooler that has learned nothing bursts every node it sees"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?

    pooler.compute(Patterns.of(0), false, true)?

    // nothing is predicted into the step, so every node's cells are on
    h.assert_eq[USize](20, pooler.active_cells().size())
    h.assert_eq[USize](0, pooler.predicted_columns().size())
    h.assert_eq[USize](0, pooler.segments())

class iso _AResetStartsOnTheStartCells is UnitTest
  fun name(): String => "after a reset the next step starts on the start cells"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?
    Patterns.learn_sequences(pooler, 2)?

    pooler.reset()
    pooler.compute(Patterns.of(2), false, true)?

    // one cell per active node, and it is the start cell
    let active = pooler.active_cells()
    h.assert_eq[USize](10, active.size())
    for cell in active.values() do
      h.assert_eq[USize](0, cell % 2)
    end

class iso _ALearnedSequenceIsPredicted is UnitTest
  fun name(): String => "a learned sequence is predicted, a node at a time"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?
    Patterns.learn_sequences(pooler, 10)?

    // the reference: walk four of the five patterns and expect every one of the
    // next pattern's nodes to be predicted
    var step: USize = 0
    while step < 4 do
      pooler.compute(Patterns.of(step), false, true)?

      let predicted = pooler.predicted_columns()
      h.assert_eq[USize](10, predicted.size())

      let next = Patterns.of(step + 1)
      for column in predicted.values() do
        h.assert_true(
          next.contains(column),
          "column " + column.string() + " belongs to the next pattern")
      end

      step = step + 1
    end

class iso _TheOutputIsWhatIsActiveOrPredicted is UnitTest
  fun name(): String => "the step answers with the cells that are active or predicted"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?
    Patterns.learn_sequences(pooler, 3)?

    let output = pooler.compute(Patterns.of(1), false, true)?

    for cell in pooler.active_cells().values() do
      h.assert_true(output.contains(cell), "an active cell is in the output")
    end
    for cell in pooler.predicted_cells().values() do
      h.assert_true(output.contains(cell), "a predicted cell is in the output")
    end

class iso _LearningGrowsSegments is UnitTest
  fun name(): String => "learning grows segments, and only learning does"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?

    // the first step has no step before it to learn from
    pooler.compute(Patterns.of(0), true, false)?
    h.assert_eq[USize](0, pooler.segments())

    pooler.compute(Patterns.of(1), true, false)?
    h.assert_true(pooler.segments() > 0)

class iso _AnUnusedSynapseAgesAway is UnitTest
  fun name(): String => "at the age boundary a synapse nobody needed is forgotten"

  fun apply(h: TestHelper) ? =>
    // a synapse weaker than the decay cannot survive it
    let config = TemporalPoolerConfig(
      20, 2,
      3, 2, 3,
      false,
      0.02, 0.5,
      0.1, 0.0, 1.0,
      0.05,               // global decay, stronger than any synapse here
      1, 10,
      10, 5,
      1,                  // everything unused for one step goes
      32,
      0, 0)?
    let pooler = TemporalPooler(config, 3)

    pooler.compute(Patterns.of(0), true, false)?
    pooler.compute(Patterns.of(1), true, false)?
    h.assert_true(pooler.segments() > 0)

    // two quiet steps: nothing new is learned, and what was learned ages out
    pooler.compute(Array[USize], true, false)?
    pooler.compute(Array[USize], true, false)?

    h.assert_eq[USize](0, pooler.segments())
