use "collections"
use "pony_test"
use "../htm"

// The claim these tests make is the one the repository exists for: a stream
// scored on actors gives the same answers as the same stream scored in process.

class AnomalyStreamTest is TestList
  fun name(): String => "Anomaly stream"

  fun tag tests(test: PonyTest) =>
    test(_AStreamScoredOnActorsAgreesWithOneProcess)
    test(_AStepThatBreaksThePatternIsTheAnomalousOne)
    test(_EveryStepIsAnsweredOnce)

primitive StreamFixture
  """
  Eight rounds of three inputs, then a fourth: the shape the in-process
  `anomaly-stream` example uses, so that the two can be read against each other.
  """
  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([64], [64], true, 16.0, 0.1)

  fun params(): TemporalMemoryParams val =>
    TemporalMemoryParams(64, 8, 1, 0.5, 0.5, 0.1, 0.02, 32, 4)

  fun steps(): Array[Array[Bool] val] val =>
    let answers: Array[Array[Bool] val] iso = recover iso
      Array[Array[Bool] val]
    end

    var round: USize = 0
    while round < 8 do
      answers.push(input([0; 1; 2; 3; 8; 9]))
      answers.push(input([16; 17; 18; 19; 24; 25]))
      answers.push(input([32; 33; 34; 35; 40; 41]))
      round = round + 1
    end
    answers.push(input([48; 49; 50; 51; 56; 57]))

    consume answers

  fun input(bits: ReadSeq[USize]): Array[Bool] val =>
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end
    for bit in bits.values() do
      try values(bit)? = true end
    end
    consume values

  fun in_process(stream: Array[Array[Bool] val] val): Array[F64] val ? =>
    let detector = StreamingAnomalyDetector(
      SpatialPooler(config(), 42)?, TemporalMemory(params()))
    let scores: Array[F64] iso = recover iso Array[F64] end
    for step in stream.values() do
      scores.push(detector.observe(step)?)
    end
    consume scores

actor ComparingStream is AnomalyObserver
  """
  Compares each reading on actors with what one process said about that step.
  """
  let _h: TestHelper
  let _expected: Array[F64] val
  var _seen: USize = 0
  var _agreeing: USize = 0

  new create(h: TestHelper, expected: Array[F64] val) =>
    _h = h
    _expected = expected

  be scored(score: F64, likelihood: F64) =>
    _seen = _seen + 1
    try
      if score == _expected(_seen - 1)? then
        _agreeing = _agreeing + 1
      end
    end

    if _seen == _expected.size() then
      _h.assert_eq[USize](_expected.size(), _agreeing,
        "every step scored on actors should score the same in process")
      _h.complete(true)
    end

class iso _AStreamScoredOnActorsAgreesWithOneProcess is UnitTest
  fun name(): String => "a stream scored on actors agrees with one process"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let steps = StreamFixture.steps()
    let expected = StreamFixture.in_process(steps)?

    let config = StreamFixture.config()
    let params = StreamFixture.params()
    let stream = AnomalyStream(
      Pooler(PoolerShards.build(config, 42, 16)?, Grid(config.column_dimensions)?,
        config, 0, 42),
      TemporalRegion(params, TemporalShards.build(params, 2)),
      params,
      recover iso AnomalyLikelihood()? end)

    let asker = ComparingStream(h, expected)
    for step in steps.values() do
      stream.observe(step, true, asker)
    end

actor CollectingStream is AnomalyObserver
  """
  Keeps every reading and, once they are all in, says what they were.
  """
  let _h: TestHelper
  let _scores: Array[F64] ref = Array[F64]
  let _likelihoods: Array[F64] ref = Array[F64]
  let _expected: USize

  new create(h: TestHelper, expected: USize) =>
    _h = h
    _expected = expected

  be scored(score: F64, likelihood: F64) =>
    _scores.push(score)
    _likelihoods.push(likelihood)

    if _scores.size() == _expected then
      _h.assert_eq[USize](_expected, _scores.size(), "one reading per step")
      _h.complete(true)
    end

actor WatchingStream is AnomalyObserver
  """
  Asserts, once the stream has settled, that the step that broke the pattern is
  the surprising one.
  """
  let _h: TestHelper
  let _scores: Array[F64] ref = Array[F64]
  let _expected: USize

  new create(h: TestHelper, expected: USize) =>
    _h = h
    _expected = expected

  be scored(score: F64, likelihood: F64) =>
    _scores.push(score)
    if _scores.size() < _expected then return end

    try
      let last = _scores(_scores.size() - 1)?
      var settled: F64 = 0.0
      var index: USize = _expected - 4
      while index < (_expected - 1) do
        settled = settled + _scores(index)?
        index = index + 1
      end
      settled = settled / 3.0

      _h.log("the pattern settles at " + settled.string()
        + ", the step that breaks it scores " + last.string())
      _h.assert_true(last > settled,
        "the step that breaks the pattern is the surprising one")
      _h.complete(true)
    else
      _h.fail("the scores could not be read")
      _h.complete(false)
    end

class iso _AStepThatBreaksThePatternIsTheAnomalousOne is UnitTest
  fun name(): String => "the step that breaks the pattern is the anomalous one"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let steps = StreamFixture.steps()
    let asker = WatchingStream(h, steps.size())
    let stream = _stream()?

    for step in steps.values() do
      stream.observe(step, true, asker)
    end

  fun _stream(): AnomalyStream ? =>
    let config = StreamFixture.config()
    let params = StreamFixture.params()
    AnomalyStream(
      Pooler(PoolerShards.build(config, 42, 16)?, Grid(config.column_dimensions)?,
        config, 0, 42),
      TemporalRegion(params, TemporalShards.build(params, 2)),
      params,
      recover iso AnomalyLikelihood()? end)

class iso _EveryStepIsAnsweredOnce is UnitTest
  fun name(): String => "every step is answered exactly once"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let steps = StreamFixture.steps()
    let asker = CollectingStream(h, steps.size())
    let config = StreamFixture.config()
    let params = StreamFixture.params()
    let stream = AnomalyStream(
      Pooler(PoolerShards.build(config, 42, 16)?, Grid(config.column_dimensions)?,
        config, 0, 42),
      TemporalRegion(params, TemporalShards.build(params, 2)),
      params,
      recover iso AnomalyLikelihood()? end)

    for step in steps.values() do
      stream.observe(step, true, asker)
    end
