use "pony_test"
use "../htm"

// These are the rules the pooler's two drivers share, tested where they live
// rather than through a pooler. The actors will depend on exactly this surface.

class ColumnLearningTest is TestList
  fun name(): String => "Column learning"

  fun tag tests(test: PonyTest) =>
    test(_NothingIsBoostedBeforeAnythingIsKnown)
    test(_AColumnThatNeverWinsIsStarvingAndBoosted)
    test(_ABoostMultipliesTheClaim)

primitive LearningSeam
  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([4; 4], [8], true, 1.0)

  fun grid(): Grid ? => Grid([4; 4])?

  fun learning(): ColumnLearning ? =>
    ColumnLearning(config(), grid()?, 8)

  fun overlaps(first: F64, second: F64 = 0.0): Array[F64] =>
    let values = Array[F64].init(0.0, 16)
    try
      values(0)? = first
      values(1)? = second
    end
    values

  fun winners(): Array[USize] => [0]

  fun rounds(learning': ColumnLearning, count: USize) ? =>
    var round: USize = 0
    while round < count do
      learning'.round()
      learning'.record(overlaps(1.0), winners())?
      learning'.review()?
      round = round + 1
    end

class iso _NothingIsBoostedBeforeAnythingIsKnown is UnitTest
  fun name(): String => "nothing is boosted before anything is known"

  fun apply(h: TestHelper) ? =>
    let learning = LearningSeam.learning()?
    let claims = LearningSeam.overlaps(1.0)

    h.assert_array_eq[F64](claims, learning.boosted(claims)?,
      "a fresh learner leaves every claim as it found it")
    h.assert_eq[F64](1.0, learning.boost_factor(3)?)

class iso _AColumnThatNeverWinsIsStarvingAndBoosted is UnitTest
  fun name(): String => "a column that never wins is starving, and is helped"

  fun apply(h: TestHelper) ? =>
    let learning = LearningSeam.learning()?

    // long enough for the idea of normal activity to have been worked out
    LearningSeam.rounds(learning, 50)?

    let starving = learning.starving()?
    h.assert_true(_holds(starving, 1), "a column that never claimed is starving")
    h.assert_true(not _holds(starving, 0), "the column that keeps winning is not")

    h.assert_true(learning.boost_factor(1)? > 1.0, "a starving column is boosted")
    h.assert_eq[F64](1.0, learning.boost_factor(0)?,
      "a column that is being heard needs no help")

  fun _holds(columns: ReadSeq[USize], column: USize): Bool =>
    for one in columns.values() do
      if one == column then return true end
    end
    false

class iso _ABoostMultipliesTheClaim is UnitTest
  fun name(): String => "a boost multiplies the claim it is given to"

  fun apply(h: TestHelper) ? =>
    let learning = LearningSeam.learning()?
    LearningSeam.rounds(learning, 50)?

    // both columns claim the same, so only the help can tell them apart
    let claims = LearningSeam.overlaps(5.0, 5.0)
    let helped = learning.boosted(claims)?

    h.assert_eq[F64](5.0, helped(0)?, "the column that keeps winning competes as it is")
    h.assert_true(helped(1)? > helped(0)?, "the starving column should outbid the winner")
