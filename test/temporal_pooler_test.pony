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
    test(_PoolingLearnsFromOneStepFurtherBack)
    test(_APooledPoolerPredictsTwoStepsAhead)
    test(_AnInputFromASequenceBegunEarlierIsTakenAsThatSequence)
    test(_ALengthLimitCostsNothingWhenLearningLooksBack)
    test(_AForecastNamesTheStepsAfterThisOne)

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

  fun of_value(index: USize): Array[USize] val =>
    """
    The same pattern as a value, which is what an actor is handed.
    """
    let columns: Array[USize] iso = recover iso Array[USize] end
    for column in of(index).values() do
      columns.push(column)
    end
    columns

  fun config(
    nodes: USize = 50,
    longest: USize = 32,
    learn_backtrack: USize = 5): TemporalPoolerConfig val ?
  =>
    """
    The reference's TestLearnPredict setup: two cells a node, ten synapses to a
    segment, and no pooling, over fifty nodes unless more are needed.
    """
    TemporalPoolerConfig(
      nodes, 2,           // nodes, and cells in each
      8, 10, 10,          // activation threshold, min threshold, synapses wanted
      false,              // no pooling
      0.5, 0.5,           // initial and connection permanence
      0.1, 0.0, 1.0,      // permanence increment, decrement, ceiling
      0.0,                // no global decay
      1, 10,              // update window, pam length
      10, learn_backtrack, // the two backtrack windows
      100000,             // nothing is ever aged out
      longest,            // longest sequence worth naming
      0, 0)?              // no fixed-size limits

  fun pooler(
    nodes: USize = 50,
    longest: USize = 32,
    learn_backtrack: USize = 5): TemporalPooler ?
  =>
    TemporalPooler(config(nodes, longest, learn_backtrack)?, 7)

  fun learn_cycle(subject: TemporalPooler, steps: USize) ? =>
    """
    Learn the five patterns as a cycle: no reset between them, so each follows
    the one before it and the first follows the fifth.
    """
    subject.reset()
    var step: USize = 0
    while step < steps do
      subject.compute(of(step % 5), true, false)?
      step = step + 1
    end
    subject.reset()

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

  fun learn_branches(subject: TemporalPooler, epochs: USize) ? =>
    """
    Two sequences that share a pattern: 0-1-2-3-4, and 2-8-9. Each is started
    from a reset, so the first pattern of each is the one learned from start
    cells.
    """
    var epoch: USize = 0
    while epoch < epochs do
      subject.reset()
      var index: USize = 0
      while index < 5 do
        subject.compute(of(index), true, false)?
        index = index + 1
      end

      subject.reset()
      subject.compute(of(2), true, false)?
      subject.compute(of(8), true, false)?
      subject.compute(of(9), true, false)?

      epoch = epoch + 1
    end

  fun pooled(window: USize): TemporalPooler ? =>
    """
    The same pooler, but pooling, and with a window of its own.
    """
    let pooling = TemporalPoolerConfig(
      50, 2,
      8, 10, 10,
      true,               // pooling
      0.5, 0.5,
      0.1, 0.0, 1.0,
      0.0,
      window, 10,
      10, 5,
      100000,
      32,
      0, 0)?
    TemporalPooler(pooling, 7)

  fun predicts_the_sequence(h: TestHelper, subject: TemporalPooler) ? =>
    """
    The reference's claim, and the one the pooler exists for: four steps in, the
    next pattern's ten nodes are the ones predicted.
    """
    var step: USize = 0
    while step < 4 do
      subject.compute(of(step), false, true)?

      let predicted = subject.predicted_columns()
      h.assert_eq[USize](10, predicted.size())

      let next = of(step + 1)
      for column in predicted.values() do
        h.assert_true(
          next.contains(column),
          "column " + column.string() + " belongs to the next pattern")
      end

      step = step + 1
    end

  fun predicts_the_cycle(h: TestHelper, subject: TemporalPooler) ? =>    """
    Every pattern of the cycle predicted when the one before it arrives, the
    fifth's successor being the first.
    """
    var step: USize = 0
    while step < 5 do
      subject.compute(of(step), false, true)?

      let predicted = subject.predicted_columns()
      h.assert_eq[USize](10, predicted.size())

      let next = of((step + 1) % 5)
      for column in predicted.values() do
        h.assert_true(
          next.contains(column),
          "column " + column.string() + " belongs to the next pattern")
      end

      step = step + 1
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

    Patterns.predicts_the_sequence(h, pooler)?

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

class iso _PoolingLearnsFromOneStepFurtherBack is UnitTest
  fun name(): String => "a pooling pooler learns from one step further back"

  fun apply(h: TestHelper) ? =>
    let plain = Patterns.pooler()?
    let pooled = Patterns.pooled(1)?

    Patterns.learn_sequences(plain, 2)?
    Patterns.learn_sequences(pooled, 2)?

    // the pooled pooler queues a second proposal for every cell it predicts,
    // reaching into the step before the one that predicted it
    h.assert_true(
      pooled.segments() > plain.segments(),
      "pooled " + pooled.segments().string() + " segments, plain " +
        plain.segments().string())

class iso _APooledPoolerPredictsTwoStepsAhead is UnitTest
  fun name(): String => "a pooled cell is predicted by the step before the one that predicted it"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooled(1)?
    Patterns.learn_sequences(pooler, 10)?

    var step: USize = 0
    while step < 3 do
      pooler.compute(Patterns.of(step), false, true)?

      let predicted = pooler.predicted_columns()

      // Every pooled cell learns the state one step before the one that taught
      // it, so a pattern predicts not only what followed it but what followed
      // that. The reference's own test leaves pooling off, and this is why: the
      // prediction is a union, twice as wide as the plain one.
      for column in Patterns.of(step + 1).values() do
        h.assert_true(
          predicted.contains(column),
          "the next pattern's column " + column.string())
      end
      for column in Patterns.of(step + 2).values() do
        h.assert_true(
          predicted.contains(column),
          "the pattern after that, column " + column.string())
      end

      h.assert_eq[USize](20, predicted.size(), "and nothing else")
      step = step + 1
    end

class iso _AnInputFromASequenceBegunEarlierIsTakenAsThatSequence is UnitTest
  fun name(): String =>
    "an input that continues a sequence begun earlier is taken as that sequence"

  fun apply(h: TestHelper) ? =>
    // 0-1-2-3-4 and 2-8-9, so that 8 continues a sequence that began three
    // steps ago as well as one the pooler is not following
    let pooler = Patterns.pooler(100)?
    Patterns.learn_branches(pooler, 10)?

    pooler.compute(Patterns.of(0), false, true)?
    pooler.compute(Patterns.of(1), false, true)?
    pooler.compute(Patterns.of(2), false, true)?

    // 8 is not what follows the sequence being followed, so without looking
    // further back every node of it would burst
    pooler.compute(Patterns.of(8), false, true)?

    let active = pooler.active_cells()
    h.assert_eq[USize](
      10, active.size(), "one cell a node, so 8 was predicted rather than burst")

    let continued = Patterns.of(8)
    for cell in active.values() do
      let node = cell / 2
      h.assert_true(
        continued.contains(node),
        "cell " + cell.string() + " belongs to the 8 pattern")
    end

    let predicted = pooler.predicted_columns()
    h.assert_eq[USize](10, predicted.size(), "and 9 is what is predicted next")
    for column in Patterns.of(9).values() do
      h.assert_true(
        predicted.contains(column), "column " + column.string() + " of 9")
    end

class iso _ALengthLimitCostsNothingWhenLearningLooksBack is UnitTest
  fun name(): String =>
    "a sequence learned in pieces is one path when learning may look back"

  fun apply(h: TestHelper) ? =>
    // a cycle of five patterns, learned as a cycle, with a limit of four steps:
    // the limit cuts the sequence every four steps, mid-way through it
    let looking = Patterns.pooler(50, 4, 5)?
    let blind = Patterns.pooler(50, 4, 0)?

    Patterns.learn_cycle(looking, 50)?
    Patterns.learn_cycle(blind, 50)?

    // neither lost the cycle to the limit
    Patterns.predicts_the_cycle(h, looking)?
    Patterns.predicts_the_cycle(h, blind)?

    // but the pass that could look back found where each piece began and
    // re-enforced that path, instead of beginning a fresh one every four steps
    h.assert_true(
      looking.segments() < blind.segments(),
      looking.segments().string() + " segments against " +
        blind.segments().string())

class iso _AForecastNamesTheStepsAfterThisOne is UnitTest
  fun name(): String => "a forecast names the patterns that follow, and changes nothing"

  fun apply(h: TestHelper) ? =>
    let pooler = Patterns.pooler()?
    Patterns.learn_cycle(pooler, 50)?

    pooler.compute(Patterns.of(0), false, true)?
    let was = pooler.predicted_columns()

    let forecast = pooler.predict(3)?

    // each step of the forecast is where the cycle is after that many steps
    var step: USize = 0
    while step < forecast.size() do
      let confident = forecast.nodes(step)?
      let wanted = Patterns.of(step + 1)

      h.assert_eq[USize](
        wanted.size(), confident.size(), "step " + (step + 1).string())
      for node in wanted.values() do
        h.assert_true(
          confident.contains(node),
          "node " + node.string() + " of the pattern " +
            (step + 1).string())
      end

      step = step + 1
    end

    // asking what comes next does not decide it
    h.assert_array_eq[USize](
      was, pooler.predicted_columns(), "the pooler is where it was")
