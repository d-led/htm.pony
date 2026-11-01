use "pony_test"
use "../htm"

class PoolerTest is TestList
  fun name(): String => "Pooler"

  fun tag tests(test: PonyTest) =>
    test(_ARoundReachesAnAnswer)
    test(_TwoRequestsAreAnsweredInTurn)

actor Listener is Representation
  let _h: TestHelper
  let _answers: USize
  var _seen: USize = 0

  new create(h: TestHelper, answers: USize) =>
    _h = h
    _answers = answers

  be represented(active: Array[USize] iso) =>
    let answer: Array[USize] val = consume active
    _seen = _seen + 1

    _h.assert_true(answer.size() > 0, "an answer should name at least one column")
    if _seen == _answers then
      _h.complete(true)
    end

primitive PoolerFixture
  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([4], [8], false, 1.0)

  fun band(first: USize): ColumnShard tag =>
    let columns = recover iso Array[ColumnView] end
    var column = first
    while column < (first + 2) do
      let synapses: Array[Synapse] val = recover val
        [Synapse(column % 8, 0.5); Synapse((column + 1) % 8, 0.5)]
      end
      columns.push(ColumnView(column, synapses))
      column = column + 1
    end
    ColumnShard(consume columns, 0.2)

  fun pooler(): Pooler ? =>
    let shards = recover iso Array[ColumnShard tag] end
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
    PoolerFixture.pooler()?.represent(PoolerFixture.input()?, Listener(h, 1))

class iso _TwoRequestsAreAnsweredInTurn is UnitTest
  fun name(): String => "two requests are both answered, one after the other"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)
    let pooler = PoolerFixture.pooler()?
    let listener = Listener(h, 2)
    pooler.represent(PoolerFixture.input()?, listener)
    pooler.represent(PoolerFixture.input()?, listener)
