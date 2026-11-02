use "pony_test"
use "../htm"

// The claim these tests make is the one the repository exists for: the same
// computation, arranged as actors, gives the same answer as the one in process.
// With learning in the round, the claim is about a session rather than one
// round: a shard that learned differently, or a round that learned out of
// order, would part company with the in-process pooler within a few rounds.

class PoolerLearningTest is TestList
  fun name(): String => "Pooler learning"

  fun tag tests(test: PonyTest) =>
    test(_ALearningSessionAgreesWithOneProcess)
    test(_ARoundWithoutLearningChangesNothingOnActors)

primitive PoolerSession
  """
  The session both paths run: one pattern, sixty rounds of it, and one seed.

  Sixty rounds because a column's idea of normal activity is worked out every
  fiftieth round, and a shorter session would never reach the rounds where the
  boost factors change who wins.
  """
  fun rounds(): USize => 60

  fun seed(): U64 => 5

  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64], false, 2.0)

  fun pattern(): Array[USize] => [3; 9; 14; 18; 25; 33; 41; 52]

  fun input(): Array[Bool] val =>
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end
    try
      for index in pattern().values() do
        values(index)? = true
      end
    end
    consume values

  fun one_process(learn: Bool): Array[Array[USize] val] val ? =>
    """
    What the in-process pooler answers, round by round.
    """
    let pooler = SpatialPooler(config(), seed())?
    let answers: Array[Array[USize] val] iso =
      recover iso Array[Array[USize] val] end

    var round: USize = 0
    while round < rounds() do
      answers.push(_frozen(pooler.compute(input(), learn)?))
      round = round + 1
    end

    consume answers

  fun pool(): Pooler ? =>
    let settings = config()
    Pooler(
      PoolerShards.build(settings, seed(), 16)?,
      Grid(settings.column_dimensions)?,
      settings)

  fun _frozen(values: ReadSeq[USize]): Array[USize] val =>
    let copy: Array[USize] iso = recover iso Array[USize] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

actor AgreeingAnswers is Representation
  """
  Compares each answer with what one process said about the same round.
  """
  let _h: TestHelper
  let _expected: Array[Array[USize] val] val
  var _seen: USize = 0
  var _agreed: USize = 0

  new create(h: TestHelper, expected: Array[Array[USize] val] val) =>
    _h = h
    _expected = expected

  be represented(active: Array[USize] iso, missing: USize) =>
    let answer: Array[USize] val = consume active
    _seen = _seen + 1

    _h.assert_eq[USize](0, missing, "every column should answer a learning round")

    try
      if _same(answer, _expected(_seen - 1)?) then
        _agreed = _agreed + 1
      end
    end

    if _seen == _expected.size() then
      _h.assert_eq[USize](_expected.size(), _agreed,
        "every round should give the answer one process gave")
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

class iso _ALearningSessionAgreesWithOneProcess is UnitTest
  fun name(): String => "sixty learning rounds give the same answers on actors"

  fun apply(h: TestHelper) ? =>
    h.long_test(10_000_000_000)

    let pooler = PoolerSession.pool()?
    let answerer = AgreeingAnswers(h, PoolerSession.one_process(true)?)

    var round: USize = 0
    while round < PoolerSession.rounds() do
      pooler.represent(PoolerSession.input(), true, answerer)
      round = round + 1
    end

class iso _ARoundWithoutLearningChangesNothingOnActors is UnitTest
  fun name(): String => "a session that does not learn answers as one process does"

  fun apply(h: TestHelper) ? =>
    h.long_test(10_000_000_000)

    let pooler = PoolerSession.pool()?
    let answerer = AgreeingAnswers(h, PoolerSession.one_process(false)?)

    var round: USize = 0
    while round < PoolerSession.rounds() do
      pooler.represent(PoolerSession.input(), false, answerer)
      round = round + 1
    end
