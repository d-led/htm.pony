use "pony_test"
use "../htm"

// The claim these tests make is the one the repository exists for: the same
// computation, arranged as actors, gives the same answer as the one in process.

class TemporalRegionTest is TestList
  fun name(): String => "Temporal region"

  fun tag tests(test: PonyTest) =>
    test(_ARegionAnswersWhatOneProcessAnswers)
    test(_TwoRoundsAreAnsweredInOrder)

primitive RegionFixture
  """
  A memory of four columns and four cells, where one matching synapse is enough
  to count as a prediction.
  """
  fun params(): TemporalMemoryParams val =>
    TemporalMemoryParams(4, 4, 1, 0.5, 0.5, 0.1, 0.02, 8, 4)

  fun steps(): Array[Array[USize] val] =>
    [
      recover val [0] end
      recover val [1] end
      recover val [0] end
      recover val [1] end
      recover val [0] end
      recover val [1] end
    ]

actor ComparingObserver is TemporalObserver
  """
  Compares each answer with what one process said about the same step.
  """
  let _h: TestHelper
  let _expected: Array[TemporalOutput val] val
  var _seen: USize = 0
  var _matches: USize = 0

  new create(h: TestHelper, expected: Array[TemporalOutput val] val) =>
    _h = h
    _expected = expected

  be observed(output: TemporalOutput val) =>
    _seen = _seen + 1

    try
      let wanted = _expected(_seen - 1)?
      if _same(output.active_cells, wanted.active_cells)
        and _same(output.predictive_cells, wanted.predictive_cells)
        and _same(output.bursting_columns, wanted.bursting_columns)
      then
        _matches = _matches + 1
      end
    end

    if _seen == _expected.size() then
      _h.assert_eq[USize](_expected.size(), _matches,
        "every step should match the one-process answer")
      _h.complete(true)
    end

  fun _same(left: ReadSeq[USize], right: ReadSeq[USize]): Bool =>
    if left.size() != right.size() then return false end
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? != right(index)? then return false end
        index = index + 1
      end
      true
    else
      false
    end

actor OrderObserver is TemporalObserver
  """
  Checks that the answers come back in the order the questions were asked.
  """
  let _h: TestHelper
  var _seen: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be observed(output: TemporalOutput val) =>
    if _seen == 0 then
      _h.assert_array_eq[USize]([0], output.bursting_columns,
        "the first answer should answer the first request")
    end

    if _seen == 1 then
      _h.assert_array_eq[USize]([1], output.bursting_columns,
        "the second answer should answer the second request")
    end

    _seen = _seen + 1
    if _seen == 2 then _h.complete(true) end

class iso _ARegionAnswersWhatOneProcessAnswers is UnitTest
  fun name(): String => "the same steps give the same answers on actors"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let expected: Array[TemporalOutput val] val = recover val
      let memory = TemporalMemory(RegionFixture.params())
      let answers = Array[TemporalOutput val]
      for step in RegionFixture.steps().values() do
        answers.push(memory.compute(step, true)?)
      end
      answers
    end

    let region = TemporalRegion(
      RegionFixture.params(), TemporalShards.build(RegionFixture.params(), 2))
    let observer = ComparingObserver(h, expected)

    for step in RegionFixture.steps().values() do
      region.compute(step, true, observer)
    end

class iso _TwoRoundsAreAnsweredInOrder is UnitTest
  fun name(): String => "two rounds are answered in the order they were asked for"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let region = TemporalRegion(
      RegionFixture.params(), TemporalShards.build(RegionFixture.params(), 1))
    let observer = OrderObserver(h)

    region.compute(recover val [0] end, true, observer)
    region.compute(recover val [1] end, true, observer)
