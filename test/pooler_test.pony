use "pony_test"
use "../htm"

class PoolerTest is TestList
  fun name(): String => "Pooler"

  fun tag tests(test: PonyTest) =>
    test(_ARoundReachesAnAnswer)
    test(_TwoRequestsAreAnsweredInTurn)
    test(_ASilentShardDoesNotHoldTheRoundOpen)
    test(_OnlyTheBandThatStayedSilentIsAskedAgain)

actor SilentShard is Shard
  """
  A band that never answers, which is what a shard that is slow, stuck or gone
  looks like to the pooler.
  """
  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag) => None

  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val) =>
    None

actor LateShard is Shard
  """
  A band that misses the first deadline and reports when it is asked again,
  which is what a shard that is merely slow looks like from the pooler.
  """
  let _first: USize
  var _asked: USize = 0

  new create(first: USize) =>
    _first = first

  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag) =>
    _asked = _asked + 1
    if _asked == 1 then return end

    let votes: Array[Vote] iso = recover iso Array[Vote] end
    votes.push(Vote(_first, 2.0))
    votes.push(Vote(_first + 1, 2.0))
    ballot.cast(band, consume votes)

  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val) =>
    None

actor CountingShard is Shard
  """
  A real band of columns that also counts how often it is asked: a band that
  answered must not be asked again because another one was slow.
  """
  let _inner: Shard tag
  let _h: TestHelper
  var _asked: USize = 0

  new create(inner: Shard tag, h: TestHelper) =>
    _inner = inner
    _h = h

  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag) =>
    _asked = _asked + 1
    if _asked > 1 then
      _h.fail("a band that answered was asked again")
    end
    _inner.observe(band, active, ballot)

  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val) =>
    _inner.learn(active, winners, starving)

actor Listener is Representation
  let _h: TestHelper
  let _answers: USize
  let _missing: USize
  var _seen: USize = 0

  new create(h: TestHelper, answers: USize, missing: USize = 0) =>
    _h = h
    _answers = answers
    _missing = missing

  be represented(active: Array[USize] iso, missing: USize) =>
    let answer: Array[USize] val = consume active
    _seen = _seen + 1

    _h.assert_eq[USize](_missing, missing, "the columns that never answered")
    _h.assert_true(answer.size() > 0, "an answer should name at least one column")
    if _seen == _answers then
      _h.complete(true)
    end

primitive PoolerFixture
  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([4], [8], false, 1.0)

  fun band(first: USize): Shard tag =>
    let wirings = recover iso Array[ColumnWiring] end
    var column = first
    while column < (first + 2) do
      let synapses: Array[Synapse] val = recover val
        [Synapse(column % 8, 0.5); Synapse((column + 1) % 8, 0.5)]
      end
      wirings.push(ColumnWiring(column, synapses))
      column = column + 1
    end
    ColumnShard(consume wirings, config())

  fun pooler(): Pooler ? =>
    let shards = recover iso Array[Shard tag] end
    shards.push(band(0))
    shards.push(band(2))
    Pooler(consume shards, Grid([4])?, config())

  fun input(): Array[Bool] val ? =>
    recover val
      let values = Array[Bool].init(false, 8)
      values(0)? = true
      values(1)? = true
      values(2)? = true
      values
    end

class iso _ARoundReachesAnAnswer is UnitTest
  fun name(): String => "a request comes back as a representation"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)
    PoolerFixture.pooler()?.represent(PoolerFixture.input()?, false, Listener(h, 1))

class iso _TwoRequestsAreAnsweredInTurn is UnitTest
  fun name(): String => "two requests are both answered, one after the other"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)
    let pooler = PoolerFixture.pooler()?
    let listener = Listener(h, 2)
    pooler.represent(PoolerFixture.input()?, false, listener)
    pooler.represent(PoolerFixture.input()?, false, listener)

class iso _ASilentShardDoesNotHoldTheRoundOpen is UnitTest
  fun name(): String => "a shard that never answers does not hold the round open"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let shards: Array[Shard tag] iso = recover iso Array[Shard tag] end
    shards.push(PoolerFixture.band(0))
    shards.push(SilentShard)

    let pooler = Pooler(
      consume shards, Grid([4])?, PoolerFixture.config(), 20)

    // the band that answered holds columns 0 and 1, so the two silent ones are
    // the other half of the population
    pooler.represent(PoolerFixture.input()?, false, Listener(h, 1, 2))

class iso _OnlyTheBandThatStayedSilentIsAskedAgain is UnitTest
  fun name(): String =>
    "a band that missed the deadline is asked again, and the one that answered is not"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let shards: Array[Shard tag] iso = recover iso Array[Shard tag] end
    shards.push(CountingShard(PoolerFixture.band(0), h))
    shards.push(LateShard(2))

    let pooler = Pooler(
      consume shards, Grid([4])?, PoolerFixture.config(), 20)

    // the late band answers as soon as it is asked again, so nothing is
    // missing from the representation
    pooler.represent(PoolerFixture.input()?, false, Listener(h, 1, 0))
