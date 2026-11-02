use "pony_test"
use "../htm"
use "../htm/util"

// The reference: nupic's algorithms/anomaly_likelihood.py -
// AnomalyLikelihood.anomalyProbability, estimateAnomalyLikelihoods,
// estimateNormal and tailProbability.
//
// One thing worth knowing before reading the assertions: the likelihood is
// "one minus the probability of a sample this far out", so an ordinary step is
// not near nought. Half of all ordinary steps read above a half. What makes a
// step an anomaly is being far outside everything the estimator has seen, and
// that is what these tests ask about.

class AnomalyLikelihoodTest is TestList
  fun name(): String => "Anomaly likelihood"

  fun tag tests(test: PonyTest) =>
    test(_TheErrorFunctionMatchesKnownValues)
    test(_TheMiddleOfADistributionIsAHalf)
    test(_ADistributionOfConstantsStillSpreads)
    test(_NothingIsJudgedWhileItIsLearning)
    test(_TheFittedDistributionSitsWhereTheStreamDid)
    test(_AStepFarAboveEverythingIsAnomalous)
    test(_AStepFarBelowEverythingIsAnomalous)
    test(_AFlatStreamReadsAsOrdinaryRatherThanAverage)

primitive LikelihoodFixture
  """
  A stream of three values that repeats, and an estimator small enough to learn
  it quickly. The smoothing window is one step, so what is estimated is what was
  observed.
  """
  fun estimator(): AnomalyLikelihood ? =>
    // rounds to learn, rounds to estimate from, history kept, re-estimation
    // period, smoothing window
    AnomalyLikelihood(10, 10, 100, 5, 1)?

  fun stream(): Array[F64] => [0.4; 0.5; 0.6]

  fun learn(watching: AnomalyLikelihood, rounds: USize) ? =>
    var round: USize = 0
    while round < rounds do
      let value = try stream()(round % 3)? else 0.5 end
      watching.observe(value)?
      round = round + 1
    end

class iso _TheErrorFunctionMatchesKnownValues is UnitTest
  fun name(): String => "the error function agrees with the published values"

  fun apply(h: TestHelper) =>
    h.assert_true((Erfc.of(0.0) - 1.0).abs() < 1e-6, "erfc(0) is one")
    h.assert_true((Erfc.of(1.0) - 0.157299207).abs() < 1e-6, "erfc(1)")
    h.assert_true((Erfc.of(2.0) - 0.004677735).abs() < 1e-6, "erfc(2)")
    h.assert_true((Erfc.of(-1.0) - 1.842700793).abs() < 1e-6, "erfc(-1)")

class iso _TheMiddleOfADistributionIsAHalf is UnitTest
  fun name(): String => "a value in the middle of a distribution is neither likely nor unlikely"

  fun apply(h: TestHelper) =>
    let normal = Normal.estimate([0.0; 1.0; 2.0; 3.0; 4.0])

    h.assert_eq[F64](2.0, normal.mean)

    // a half, to the accuracy of the approximation: it is off by eight parts in
    // a hundred million at zero, which is what Erfc promises
    h.assert_true((normal.tail_probability(2.0) - 0.5).abs() < 1e-6,
      "a value at the mean has nothing beyond it on either side")

class iso _ADistributionOfConstantsStillSpreads is UnitTest
  fun name(): String => "a stream that never moves is still given room to move"

  fun apply(h: TestHelper) =>
    let normal = Normal.estimate([0.0; 0.0; 0.0])

    h.assert_eq[F64](0.03, normal.mean, "an almost-zero stream is centred above zero")
    h.assert_true(normal.spread > 0.0, "the smallest movement should not be a certainty")

class iso _NothingIsJudgedWhileItIsLearning is UnitTest
  fun name(): String => "while it is learning, every score reads as a half"

  fun apply(h: TestHelper) ? =>
    let estimator = LikelihoodFixture.estimator()?

    // ten to learn and ten to estimate from: a distribution from ten points is
    // not a distribution yet
    var round: USize = 0
    while round < 20 do
      h.assert_eq[F64](0.5, estimator.observe(0.5)?)
      round = round + 1
    end

    h.assert_true(estimator.fitted() is None, "nothing was fitted yet")

class iso _TheFittedDistributionSitsWhereTheStreamDid is UnitTest
  fun name(): String => "the distribution it fits sits in the middle of the stream"

  fun apply(h: TestHelper) ? =>
    let estimator = LikelihoodFixture.estimator()?
    LikelihoodFixture.learn(estimator, 60)?

    match estimator.fitted()
    | let normal: Normal =>
      h.assert_true(normal.mean > 0.45, "the middle of the stream should be near a half")
      h.assert_true(normal.mean < 0.55, "the middle of the stream should be near a half")
    else
      h.fail("a stream of sixty scores should have been fitted")
    end

class iso _AStepFarAboveEverythingIsAnomalous is UnitTest
  fun name(): String => "a step far above everything seen reads as an anomaly"

  fun apply(h: TestHelper) ? =>
    let estimator = LikelihoodFixture.estimator()?
    LikelihoodFixture.learn(estimator, 60)?

    h.assert_true(estimator.observe(0.9)? > 0.999,
      "a step four spreads above the stream should be certain")

class iso _AStepFarBelowEverythingIsAnomalous is UnitTest
  fun name(): String => "a step far below everything seen reads as an anomaly too"

  fun apply(h: TestHelper) ? =>
    let estimator = LikelihoodFixture.estimator()?
    LikelihoodFixture.learn(estimator, 60)?

    h.assert_true(estimator.observe(0.1)? > 0.999,
      "being far too quiet is as unusual as being far too loud")

class iso _AFlatStreamReadsAsOrdinaryRatherThanAverage is UnitTest
  fun name(): String => "a stream that never moves reads as ordinary, not as average"

  fun apply(h: TestHelper) ? =>
    // the estimator's floors decide this one, not the data: the mean is held at
    // 0.03 and the variance at 0.0003, so a score of exactly zero sits about
    // 1.7 spread-widths below the fitted middle. That is an ordinary sample, and
    // one minus its tail probability is about 0.958 - for every step, forever.
    let watching = AnomalyLikelihood(10, 10, 200, 5, 10)?

    var last: F64 = 0.5
    var step: USize = 0
    while step < 100 do
      last = watching.observe(0.0)?
      step = step + 1
    end

    h.assert_true(
      (last - 0.958).abs() < 0.001,
      "a flat stream reads as very ordinary: " + last.string())
