use "pony_test"
use "../htm"

class CorticalColumnTest is TestList
  fun name(): String => "Cortical column"

  fun tag tests(test: PonyTest) =>
    test(_AColumnVotesItsOverlap)
    test(_AColumnWithNoActiveInputAbstains)

actor VoteWatcher is Tally
  let _h: TestHelper
  let _column: USize
  let _overlap: F64

  new create(h: TestHelper, column: USize, overlap: F64) =>
    _h = h
    _column = column
    _overlap = overlap

  be tallied(votes: Array[Vote] iso) =>
    let received: Array[Vote] val = consume votes

    _h.assert_eq[USize](1, received.size(), "one column, one vote")
    for cast in received.values() do
      _h.assert_eq[USize](_column, cast.column, "which column voted")
      _h.assert_eq[F64](_overlap, cast.overlap, "the overlap it reported")
    end
    _h.complete(true)

class iso _AColumnVotesItsOverlap is UnitTest
  fun name(): String => "a column votes the count of its active connected synapses"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let synapses: Array[Synapse] val = recover val
      [Synapse(0, 0.5); Synapse(1, 0.5)]
    end
    let input: Array[Bool] val = recover val [true; false] end

    CorticalColumn(3, synapses, 0.2).consider(input, BallotBox(VoteWatcher(h, 3, 1.0), 1))

class iso _AColumnWithNoActiveInputAbstains is UnitTest
  fun name(): String => "a column with nothing active to claim reports no overlap"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let synapses: Array[Synapse] val = recover val
      [Synapse(0, 0.5)]
    end
    let input: Array[Bool] val = recover val [false] end

    CorticalColumn(0, synapses, 0.2).consider(input, BallotBox(VoteWatcher(h, 0, 0.0), 1))
