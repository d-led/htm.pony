use "pony_test"
use "../htm"

// The claim these tests make is the one the repository exists for: the same
// computation, arranged as actors, gives the same answer as the one in process.

class TemporalRegionTest is TestList
  fun name(): String => "Temporal region"

  fun tag tests(test: PonyTest) =>
    test(_ARegionAnswersWhatOneProcessAnswers)
    test(_TwoRoundsAreAnsweredInOrder)
    test(_ASilentBandIsNamedInTheAnswer)
    test(_ABusyBandIsAskedAgain)
    test(_ABandBusyTwiceIsStillHeardFrom)
    test(_PatienceIsBoundedByTheRetriesItWasGiven)
    test(_AMissingBandNamesTheColumnsItOwed)
    test(_AHandedOverBandAnswersTheNextRound)
    test(_ARegionWithNoBandsAnswersAtOnce)

actor SilentBand is TemporalBand
  """
  A band that never answers, which is what a shard stuck inside a behaviour it
  will not leave looks like. Actors in one process cannot be gone: the region
  holds every band, so silence means work, not death.
  """
  be take(band: USize, pass: TemporalPass val, sink: TemporalSink tag) => None

actor LateBand is TemporalBand
  """
  A band that misses the first few deadlines and answers when it is asked often
  enough - what a shard that is merely busy looks like from the region.
  """
  let _ignored: USize
  var _asked: USize = 0

  new create(ignored: USize = 1) =>
    _ignored = ignored

  be take(band: USize, pass: TemporalPass val, sink: TemporalSink tag) =>
    _asked = _asked + 1
    if _asked <= _ignored then return end

    if pass.predicting then
      sink.predicted(band, recover val Array[USize] end)
    else
      sink.activated(
        band,
        recover val Array[USize] end,
        recover val Array[USize] end,
        recover val Array[USize] end)
    end

actor NoCellsObserver is TemporalObserver
  """
  Checks that a step with no bands behind it comes back empty rather than
  never.
  """
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be observed(output: TemporalOutput val) =>
    _h.assert_eq[USize](0, output.active_cells.size())
    _h.assert_eq[USize](0, output.predictive_cells.size())
    _h.complete(true)

actor MissingObserver is TemporalObserver
  """
  Checks which bands an answer says never spoke.
  """
  let _h: TestHelper
  let _wanted: Array[USize] val

  new create(h: TestHelper, wanted: Array[USize] val) =>
    _h = h
    _wanted = wanted

  be observed(output: TemporalOutput val) =>
    _h.assert_array_eq[USize](
      _wanted, output.missing, "the bands the answer is missing")
    _h.complete(true)

actor SwappingObserver is TemporalObserver
  """
  Checks the round before a band swap and the round after it.
  """
  let _h: TestHelper
  var _seen: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be observed(output: TemporalOutput val) =>
    if _seen == 0 then
      _h.assert_eq[USize](0, output.missing.size(), "the first round has its band")
    else
      _h.assert_array_eq[USize]([0], output.missing, "the new band never answers")
      _h.complete(true)
    end

    _seen = _seen + 1

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

class iso _ASilentBandIsNamedInTheAnswer is UnitTest
  fun name(): String => "a silent band does not hold the round open, and is named"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let shards: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    shards.push(TemporalColumnShard(0, 2, RegionFixture.params()))
    shards.push(SilentBand)

    let region = TemporalRegion(RegionFixture.params(), consume shards, 50)
    region.compute(recover val [0] end, true, MissingObserver(h, recover val [1] end))

class iso _ABusyBandIsAskedAgain is UnitTest
  fun name(): String => "a band that was busy is asked once more, and counts"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let shards: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    shards.push(TemporalColumnShard(0, 2, RegionFixture.params()))
    shards.push(LateBand)

    // the band answers on the second ask, so nothing is missing
    let region = TemporalRegion(RegionFixture.params(), consume shards, 50)
    region.compute(
      recover val [0] end, true, MissingObserver(h, recover val Array[USize] end))

class iso _ABandBusyTwiceIsStillHeardFrom is UnitTest
  fun name(): String =>
    "a band that missed two deadlines is asked again and counts"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let shards: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    shards.push(TemporalColumnShard(0, 2, RegionFixture.params()))
    shards.push(LateBand(2))

    // two retries, each waiting longer than the last: the band answers on the
    // third ask, so nothing is missing
    let region = TemporalRegion(RegionFixture.params(), consume shards, 20, 2)
    region.compute(
      recover val [0] end, true, MissingObserver(h, recover val Array[USize] end))

class iso _PatienceIsBoundedByTheRetriesItWasGiven is UnitTest
  fun name(): String => "a band that never answers is given up on, not waited for forever"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let shards: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    shards.push(TemporalColumnShard(0, 2, RegionFixture.params()))
    shards.push(SilentBand)

    // more patience than one retry, and still an answer rather than a wait
    let region = TemporalRegion(RegionFixture.params(), consume shards, 10, 3)
    region.compute(recover val [0] end, true, MissingObserver(h, recover val [1] end))

class iso _AMissingBandNamesTheColumnsItOwed is UnitTest
  fun name(): String => "a band that never answered names the columns it owed"

  fun apply(h: TestHelper) =>
    // four columns in bands of two: band 1 is columns 2 and 3
    h.assert_array_eq[USize](
      [2; 3],
      _missing(1).missing_columns(RegionFixture.params(), 2),
      "the columns of the band that stayed silent")

    // a last band shorter than the width owes only the columns that are there
    h.assert_array_eq[USize](
      [3],
      _missing(1).missing_columns(RegionFixture.params(), 3),
      "a band that runs past the population owes what is inside it")

    h.assert_array_eq[USize](
      Array[USize],
      _missing(6).missing_columns(RegionFixture.params(), 2),
      "a band past the population owes nothing")

    h.assert_array_eq[USize](
      Array[USize],
      _missing(1).missing_columns(RegionFixture.params(), 0),
      "and a width of zero says nothing was ever cut that way")

  fun _missing(band: USize): TemporalOutput =>
    TemporalOutput(
      recover val Array[USize] end,
      recover val Array[USize] end,
      recover val Array[USize] end,
      recover val [band] end)

class iso _AHandedOverBandAnswersTheNextRound is UnitTest
  fun name(): String => "a band handed over later answers the next round"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let first: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    first.push(TemporalColumnShard(0, 4, RegionFixture.params()))

    let region = TemporalRegion(RegionFixture.params(), consume first, 50)
    let observer = SwappingObserver(h)

    region.compute(recover val [0] end, true, observer)

    // handed over while the first round is still out: the swap waits for it
    let later: Array[TemporalBand tag] iso = recover iso Array[TemporalBand tag] end
    later.push(SilentBand)
    region.reconfigure(consume later)

    region.compute(recover val [1] end, true, observer)

class iso _ARegionWithNoBandsAnswersAtOnce is UnitTest
  fun name(): String => "a region with no bands answers at once, with nothing"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let none: Array[TemporalBand tag] val = recover val Array[TemporalBand tag] end
    let region = TemporalRegion(RegionFixture.params(), none)

    // no deadline: nothing to wait for, and no answer that could be late
    region.compute(recover val [0] end, true, NoCellsObserver(h))
