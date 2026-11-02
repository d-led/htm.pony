use "collections"
use "pony_test"
use "../htm"

class ColumnShardTest is TestList
  fun name(): String => "Column shard"

  fun tag tests(test: PonyTest) =>
    test(_AShardVotesForEveryColumnItOwns)

actor ShardWatcher is Tally
  """
  Checks the band's votes: one per column, each reporting the overlap that
  column reaches.
  """
  let _h: TestHelper
  let _overlaps: Array[F64] val

  new create(h: TestHelper, overlaps: Array[F64] val) =>
    _h = h
    _overlaps = overlaps

  be tallied(votes: Array[Vote] iso, silent: Array[USize] val) =>
    let received: Array[Vote] val = consume votes
    let seen = Set[USize]

    _h.assert_eq[USize](_overlaps.size(), received.size(), "one vote per column")
    for cast in received.values() do
      _h.assert_false(seen.contains(cast.column), "every vote names a different column")
      seen.set(cast.column)

      try
        _h.assert_eq[F64](_overlaps(cast.column)?, cast.overlap,
          "the overlap that column reaches")
      end
    end
    _h.complete(true)

class iso _AShardVotesForEveryColumnItOwns is UnitTest
  fun name(): String => "a shard reports what each column in its band reaches"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let sees_the_input: Array[Synapse] val = recover val [Synapse(0, 0.5)] end
    let misses_the_input: Array[Synapse] val = recover val [Synapse(1, 0.5)] end
    let wirings: Array[ColumnWiring] val = recover val
      [ColumnWiring(0, sees_the_input); ColumnWiring(1, misses_the_input)]
    end
    let input: Array[Bool] val = recover val [true; false] end

    // two votes means the round needs both of them, however they are grouped
    let ballot = BallotBox(ShardWatcher(h, recover val [1.0; 0.0] end), 2)
    ColumnShard(wirings, SpatialPoolerConfig([2], [2], false, 2.0)).observe(0, input, ballot)
