use "pony_test"
use "../htm"

primitive PredictionFixture
  fun predictor(): PredictionClassifier ? =>
    PredictionClassifier(
      _memory(),
      2,
      0.1)?

  fun two_step(): PredictionClassifier ? =>
    PredictionClassifier(
      _memory(),
      3,
      0.1,
      2)?

  fun _memory(): TemporalMemory =>
    TemporalMemory(TemporalMemoryParams(
      where
        columns' = 4,
        cells_per_column' = 4,
        activation_threshold' = 1,
        max_synapses' = 8,
        max_segments_per_cell' = 4))

  fun teaches_a_cycle(target: PredictionClassifier) ? =>
    """
    Three steps that repeat: column 0 carries label 0, column 1 label 1, column
    2 label 2.
    """
    var round: USize = 0
    while round < 20 do
      target.observe([0], 0, true)?
      target.observe([1], 1, true)?
      target.observe([2], 2, true)?
      round = round + 1
    end

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
    test(_ATwoStepPredictorAnswersTwoStepsAhead)
    test(_AOneStepPredictorRefusesToAnswerFurther)

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

class iso _ATwoStepPredictorAnswersTwoStepsAhead is UnitTest
  fun name(): String => "a predictor of two steps answers with the label two steps ahead"

  fun apply(h: TestHelper) ? =>
    let predictor = PredictionFixture.two_step()?
    PredictionFixture.teaches_a_cycle(predictor)?

    // the first step again, this time with no label to settle anything
    predictor.observe([0], None, false)?

    h.assert_eq[USize](1, predictor.best_at(1)?)
    h.assert_eq[USize](2, predictor.best_at(2)?)

class iso _AOneStepPredictorRefusesToAnswerFurther is UnitTest
  fun name(): String => "a predictor of one step refuses to answer further"

  fun apply(h: TestHelper) ? =>
    let predictor = PredictionFixture.predictor()?
    let _ = predictor.observe([0], None, false)?

    var refused = false
    try
      predictor.probabilities_at(2)?
    else
      refused = true
    end

    h.assert_true(refused, "there is no second step to answer for")
