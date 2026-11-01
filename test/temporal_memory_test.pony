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
    test(_AnUnrelatedColumnIsNotPredicted)
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

class iso _AColumnOutsideTheMemoryIsRefused is UnitTest
  fun name(): String => "a column the memory was not built for is refused"

  fun apply(h: TestHelper) =>
    let memory = TemporalFixture.memory()

    try
      memory.compute([99], false)?
      h.fail("a column past the end of the memory should be refused")
    end
