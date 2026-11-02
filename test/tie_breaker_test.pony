use "pony_test"
use "../htm"

class TieBreakerTest is TestList
  fun name(): String => "Tie breaker"

  fun tag tests(test: PonyTest) =>
    test(_EveryNudgeIsSmallerThanTheGapBetweenClaims)
    test(_TheSameSeedGivesTheSameNoise)
    test(_ANudgeBreaksTheTieWithoutInventingAClaim)

class iso _EveryNudgeIsSmallerThanTheGapBetweenClaims is UnitTest
  fun name(): String =>
    "a nudge cannot overturn a claim that is genuinely stronger"

  fun apply(h: TestHelper) =>
    let noise = TieBreaker.of(100, 3)

    var low: F64 = 1.0
    var high: F64 = 0.0
    for value in noise.values() do
      h.assert_true(value >= 0.0, "a nudge is not negative")
      h.assert_true(value < 0.01, "a nudge stays below a hundredth")
      if value < low then low = value end
      if value > high then high = value end
    end

    // otherwise it could not separate two columns claiming the same thing
    h.assert_true((high - low) > 0.005, "the nudges are not spread out")

class iso _TheSameSeedGivesTheSameNoise is UnitTest
  fun name(): String => "the same seed gives the same nudges, another seed gives others"

  fun apply(h: TestHelper) =>
    let first = TieBreaker.of(20, 7)
    let again = TieBreaker.of(20, 7)
    let other = TieBreaker.of(20, 8)

    var different: USize = 0
    var column: USize = 0
    while column < 20 do
      try
        h.assert_eq[F64](first(column)?, again(column)?,
          "the same seed is the same pooler")
        if first(column)? != other(column)? then
          different = different + 1
        end
      end
      column = column + 1
    end

    h.assert_true(different > 0, "another seed nudges differently")

class iso _ANudgeBreaksTheTieWithoutInventingAClaim is UnitTest
  fun name(): String => "a nudge is added to a claim, and adds no claim of its own"

  fun apply(h: TestHelper) ? =>
    let noise = TieBreaker.of(3, 11)
    let claims: Array[F64] = [5.0; 5.0; 0.0]
    let nudged = TieBreaker.nudged(claims, noise)?

    h.assert_eq[F64](5.0 + noise(0)?, nudged(0)?, "a claim plus its own nudge")
    h.assert_eq[F64](5.0 + noise(1)?, nudged(1)?, "a claim plus its own nudge")
    h.assert_eq[F64](0.0, nudged(2)?, "a column that matched nothing claims nothing")

    h.assert_eq[F64](5.0, claims(0)?, "the claim itself is left as it was")
    h.assert_true(nudged(0)? != nudged(1)?, "equal claims are no longer equal")
