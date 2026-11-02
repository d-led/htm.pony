use "pony_test"
use "../htm"

primitive TemporalFixture
  """
  A memory small enough to reason about: four columns, four cells each, and one
  matching synapse is enough to count as a prediction.
  """
  fun params(cells_per_column: USize = 4): TemporalMemoryParams val =>
    TemporalMemoryParams(
      4,
      cells_per_column,
      1,
      0.5,
      0.5,
      0.1,
      0.02,
      8,
      4)

  fun memory(): TemporalMemory =>
    TemporalMemory(params())

  fun swift_memory(): TemporalMemory =>
    """
    The same, but a synapse moves a long way when it is punished, so a test can
    reach the outcome in a few steps.
    """
    TemporalMemory(TemporalMemoryParams(4, 4, 1, 0.5, 0.5, 0.1, 0.2, 8, 4))

  fun teaches(target: TemporalMemory, first: USize, second: USize) ? =>
    """
    Show one column, then another, twice, so the pair is learned.
    """
    var round: USize = 0
    while round < 2 do
      target.compute([first], true)?
      target.compute([second], true)?
      round = round + 1
    end

  fun columns_of(cells: ReadSeq[USize], shape: TemporalMemoryParams val): Array[USize] =>
    let result = Array[USize]
    for cell in cells.values() do
      let column = shape.column_of(cell)
      var seen = false
      for known in result.values() do
        if known == column then seen = true end
      end
      if not seen then result.push(column) end
    end
    result

class TemporalMemoryTest is TestList
  fun name(): String => "Temporal memory"

  fun tag tests(test: PonyTest) =>
    test(_AFreshMemoryPredictsNothing)
    test(_AColumnWithNoPredictionBursts)
    test(_ALearnedPairIsPredicted)
    test(_APredictedColumnDoesNotBurst)
    test(_ASegmentNeedsEnoughActiveSynapsesToPredict)
    test(_AnUnrelatedColumnIsNotPredicted)
    test(_ASegmentThatPredictsWronglyIsForgotten)
    test(_AColumnOutsideTheMemoryIsRefused)

class iso _AFreshMemoryPredictsNothing is UnitTest
  fun name(): String => "a fresh memory predicts nothing"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.memory()
    let output = memory.compute([0], false)?

    h.assert_eq[USize](0, output.predictive_cells.size())

class iso _AColumnWithNoPredictionBursts is UnitTest
  fun name(): String => "a column with no prediction bursts"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.memory()
    let output = memory.compute([0], false)?

    h.assert_eq[USize](4, output.active_cells.size())
    h.assert_array_eq[USize]([0], output.bursting_columns)

class iso _ALearnedPairIsPredicted is UnitTest
  fun name(): String => "after learning one column then another, the first predicts the second"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.memory()
    TemporalFixture.teaches(memory, 0, 1)?

    let output = memory.compute([0], false)?

    let predicted = TemporalFixture.columns_of(output.predictive_cells, memory.params)
    h.assert_array_eq[USize]([1], predicted)

class iso _APredictedColumnDoesNotBurst is UnitTest
  fun name(): String => "a predicted column activates only the predicted cells"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.memory()
    TemporalFixture.teaches(memory, 0, 1)?

    memory.compute([0], false)?
    let output = memory.compute([1], false)?

    h.assert_eq[USize](0, output.bursting_columns.size())
    h.assert_eq[USize](1, output.active_cells.size())

class iso _AnUnrelatedColumnIsNotPredicted is UnitTest
  fun name(): String => "a column that was never learned is not predicted"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.memory()
    TemporalFixture.teaches(memory, 0, 1)?

    memory.compute([0], false)?
    let output = memory.compute([2], false)?

    let predicted = TemporalFixture.columns_of(output.predictive_cells, memory.params)
    h.assert_true(
      not _contains(predicted, 2),
      "column 2 was never taught and should not be predicted")

  fun _contains(values: ReadSeq[USize], wanted: USize): Bool =>
    for value in values.values() do
      if value == wanted then return true end
    end
    false

class iso _ASegmentThatPredictsWronglyIsForgotten is UnitTest
  fun name(): String => "a segment that keeps predicting wrongly is forgotten"

  fun apply(h: TestHelper) ? =>
    let memory = TemporalFixture.swift_memory()
    TemporalFixture.teaches(memory, 0, 1)?

    let after_first = memory.compute([0], false)?
    h.assert_true(
      _contains(TemporalFixture.columns_of(after_first.predictive_cells, memory.params), 1),
      "column 0 should predict column 1 before the sequence changes")

    // column 0 is followed by column 2 from now on, so the segment that expected
    // column 1 is wrong every time it fires
    var round: USize = 0
    while round < 6 do
      memory.compute([0], true)?
      memory.compute([2], true)?
      round = round + 1
    end

    let predicted = TemporalFixture.columns_of(memory.compute([0], false)?.predictive_cells, memory.params)
    h.assert_true(
      not _contains(predicted, 1),
      "a segment that never comes true should stop predicting column 1")

  fun _contains(values: ReadSeq[USize], wanted: USize): Bool =>
    for value in values.values() do
      if value == wanted then return true end
    end
    false

class iso _AColumnOutsideTheMemoryIsRefused is UnitTest
  fun name(): String => "a column the memory was not built for is refused"

  fun apply(h: TestHelper) =>
    let memory = TemporalFixture.memory()

    try
      memory.compute([99], false)?
      h.fail("a column past the end of the memory should be refused")
    end

class iso _ASegmentNeedsEnoughActiveSynapsesToPredict is UnitTest
  fun name(): String => "a segment needs enough active synapses to be a prediction"

  // the Go reference: temporalMemory.computePredictiveCells, which leaves every
  // segment that matches too little out of the prediction
  fun apply(h: TestHelper) ? =>
    // the same sequence, learned by two memories that differ in one number: how
    // many active synapses make a segment a prediction. Their segments are
    // allowed one synapse each, so the patient one can never reach two.
    let eager = TemporalMemory(TemporalMemoryParams(4, 4, 1, 0.5, 0.5, 0.1, 0.02, 1, 4))
    let patient = TemporalMemory(TemporalMemoryParams(4, 4, 2, 0.5, 0.5, 0.1, 0.02, 1, 4))

    for memory in [eager; patient].values() do
      TemporalFixture.teaches(memory, 0, 1)?
    end

    let by_eager = eager.compute([0], false)?
    let by_patient = patient.compute([0], false)?

    let predicted = TemporalFixture.columns_of(by_eager.predictive_cells, eager.params)
    h.assert_array_eq[USize]([1], predicted)

    h.assert_eq[USize](0, by_patient.predictive_cells.size(),
      "one active synapse is not a prediction when two are needed")
