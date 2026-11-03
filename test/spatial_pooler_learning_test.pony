// Follows spatialPoolerBoost_test.go in htm-community/htm (MIT) with this
// repository's vocabulary. See docs/sources.md.
use "pony_test"
use "../htm"

// The Go reference: spatialPooler.Compute with learn, adaptSynapses,
// updateDutyCycles, bumpUpWeakColumns, updateBoostFactors, updateMinDutyCycles.
//
// What these tests claim is what the reference delivers: a winner moves its
// permanences towards the input, a column that keeps losing is helped, and a
// round without learning changes nothing. What they deliberately do not claim
// is that a trained pooler recognises a damaged pattern better than an
// untrained one: that depends on the kind of damage, and
// examples/pooler-training-value measures both kinds instead of asserting one.

class SpatialPoolerLearningTest is TestList
  fun name(): String => "Spatial pooler learning"

  fun tag tests(test: PonyTest) =>
    test(_AWinnerMovesItsPermanencesTowardsTheInput)
    test(_ARoundWithoutLearningChangesNothing)
    test(_AColumnThatKeepsLosingIsBoosted)

primitive LearningFixture
  """
  A pooler small enough to reason about: sixty-four columns, two winners per
  neighbourhood, an input of sixty-four bits.
  """
  fun config(): SpatialPoolerConfig =>
    SpatialPoolerConfig([8; 8], [64]
      where global_inhibition' = false, num_active_columns_per_inh_area' = 2.0)

  fun input(on: ReadSeq[USize], width: USize = 64): Array[Bool] =>
    let values = Array[Bool].init(false, width)
    try
      for index in on.values() do
        values(index)? = true
      end
    end
    values

  fun pattern(): Array[USize] => [3; 9; 14; 18; 25; 33; 41; 52]

  fun permanences(column: Column): Array[F64] =>
    let values = Array[F64]
    for synapse in column.synapses.values() do
      values.push(synapse.permanence)
    end
    values

  fun trained(rounds: USize, seen: ReadSeq[USize]): SpatialPooler ? =>
    let pooler = SpatialPooler(config(), 5)?
    var round: USize = 0
    while round < rounds do
      pooler.compute(input(seen), true)?
      round = round + 1
    end
    pooler

class iso _AWinnerMovesItsPermanencesTowardsTheInput is UnitTest
  fun name(): String => "a column that wins moves its permanences towards the input"

  fun apply(h: TestHelper) ? =>
    let pooler = SpatialPooler(LearningFixture.config(), 5)?
    let input = LearningFixture.input(LearningFixture.pattern())

    // what the pooler answers before it has learned anything
    let winners = pooler.compute(input)?
    h.assert_true(winners.size() > 0, "the pattern should be represented")

    let winner = winners(0)?
    let before = LearningFixture.permanences(pooler.columns(winner)?)

    pooler.compute(input, true)?

    let column = pooler.columns(winner)?
    let after = LearningFixture.permanences(column)
    h.assert_eq[USize](before.size(), after.size())

    var index: USize = 0
    while index < after.size() do
      let synapse = column.synapses(index)?
      let was = before(index)?
      let now = after(index)?

      if input(synapse.input)? then
        h.assert_true(now > was, "the column should believe more in an input it won with")
      else
        h.assert_true(now <= was, "the column should believe less in an input that was silent")
      end
      index = index + 1
    end

class iso _ARoundWithoutLearningChangesNothing is UnitTest
  fun name(): String => "a round that does not learn leaves the pooler as it found it"

  fun apply(h: TestHelper) ? =>
    let pooler = LearningFixture.trained(10, LearningFixture.pattern())?
    let input = LearningFixture.input(LearningFixture.pattern())

    let before = Array[Array[F64]]
    for column in pooler.columns.values() do
      before.push(LearningFixture.permanences(column))
    end

    let first = pooler.compute(input)?
    let second = pooler.compute(input)?

    h.assert_array_eq[USize](first, second)

    var index: USize = 0
    while index < before.size() do
      h.assert_array_eq[F64](before(index)?, LearningFixture.permanences(pooler.columns(index)?))
      index = index + 1
    end

class iso _AColumnThatKeepsLosingIsBoosted is UnitTest
  fun name(): String => "a column that keeps losing is helped towards winning"

  fun apply(h: TestHelper) ? =>
    // long enough for the minimum duty cycles to have been worked out
    let pooler = LearningFixture.trained(60, LearningFixture.pattern())?
    let winners = pooler.compute(LearningFixture.input(LearningFixture.pattern()))?

    var heard: USize = 0
    for winner in winners.values() do
      h.assert_eq[F64](1.0, pooler.boost_factor(winner)?,
        "a column that is being heard needs no help")
      heard = heard + 1
    end
    h.assert_true(heard > 0, "the pattern should still be represented")

    var helped: USize = 0
    var index: USize = 0
    while index < pooler.size() do
      if pooler.boost_factor(index)? > 1.0 then helped = helped + 1 end
      index = index + 1
    end
    h.assert_true(helped > 0, "columns that never win should be boosted")
