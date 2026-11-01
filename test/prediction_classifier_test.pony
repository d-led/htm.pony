use "pony_test"
use "../htm"

primitive PredictionFixture
  fun predictor(): PredictionClassifier ? =>
    PredictionClassifier(
      TemporalMemory(TemporalMemoryParams(4, 4, 1, 0.5, 0.5, 0.1, 0.02, 8, 4)),
      2,
      0.1)?

  fun teaches(target: PredictionClassifier) ? =>
    """
    Column 0 always carries label 0 and is always followed by column 1, which
    carries label 1.
    """
    var round: USize = 0
    while round < 20 do
      target.observe([0], 0, true)?
      target.observe([1], 1, true)?
      round = round + 1
    end

class PredictionClassifierTest is TestList
  fun name(): String => "Prediction classifier"

  fun tag tests(test: PonyTest) =>
    test(_AFreshPredictorPrefersNoLabel)
    test(_TheNextLabelIsPredictedBeforeItArrives)
    test(_ThePredictionIsForgottenWhenTheSequenceChanges)

class iso _AFreshPredictorPrefersNoLabel is UnitTest
  fun name(): String => "a fresh predictor prefers no label"

  fun apply(h: TestHelper) ? =>
    let predictor = PredictionFixture.predictor()?
    let probabilities = predictor.observe([0], None, false)?

    h.assert_eq[F64](0.5, probabilities(0)?)
    h.assert_eq[F64](0.5, probabilities(1)?)

class iso _TheNextLabelIsPredictedBeforeItArrives is UnitTest
  fun name(): String => "the label of the next step is predicted before it arrives"

  fun apply(h: TestHelper) ? =>
    let predictor = PredictionFixture.predictor()?
    PredictionFixture.teaches(predictor)?

    // show the first step again and read the prediction without giving a label
    let probabilities = predictor.observe([0], None, false)?

    h.assert_eq[USize](1, predictor.best())
    h.assert_true(
      probabilities(1)? > probabilities(0)?,
      "the label that follows the first step should be the likely one")

class iso _ThePredictionIsForgottenWhenTheSequenceChanges is UnitTest
  fun name(): String => "a label that stops arriving stops being predicted"

  fun apply(h: TestHelper) ? =>
    let predictor = PredictionFixture.predictor()?
    PredictionFixture.teaches(predictor)?

    // column 0 now leads nowhere it has seen before
    var round: USize = 0
    while round < 20 do
      predictor.observe([2], 0, true)?
      predictor.observe([3], 0, true)?
      round = round + 1
    end

    let probabilities = predictor.observe([2], None, false)?

    h.assert_true(
      probabilities(1)? < 0.5,
      "label 1 was not seen with this sequence and should not be predicted")
