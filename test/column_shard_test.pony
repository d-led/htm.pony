use "pony_test"
use "../htm"

class ColumnShardTest is TestList
  fun name(): String => "Column shard"

  fun tag tests(test: PonyTest) =>
    test(_AShardVotesForEveryColumnItOwns)

actor ShardWatcher is Tally
  let _h: TestHelper
  let _expected: USize

  new create(h: TestHelper, expected: USize) =>
    _h = h
    _expected = expected

  be tallied(votes: Array[Vote] iso) =>
    let received: Array[Vote] val = consume votes

    _h.assert_eq[USize](_expected, received.size(), "votes from the band")
    for cast in received.values() do
      _h.assert_true(cast.column < _expected, "every column within the band should vote")
    end
    _h.complete(true)

class iso _AShardVotesForEveryColumnItOwns is UnitTest
  fun name(): String => "a shard reports one vote for each column in its band"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let field: Array[Synapse] val = recover val [Synapse(0, 0.5)] end
    let columns: Array[ColumnView] val = recover val
      [ColumnView(0, field); ColumnView(1, field)]
    end
    let input: Array[Bool] val = recover val [true] end

    // two votes means the round needs both of them, however they are grouped
    let ballot = BallotBox(ShardWatcher(h, 2), 2)
    ColumnShard(columns, 0.2).observe(input, ballot)
