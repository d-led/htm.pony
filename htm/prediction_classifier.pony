class PredictionClassifier
  """
  Classifies what the temporal memory expects, not what it sees.

  The classifier on its own answers "what do these cells mean". Fed the cells
  that are active, that is a description of the present. Fed the cells that are
  *predicted*, the same classifier answers what comes next - and it can answer
  before the next input arrives, which is the whole point of predicting.

  The pairing is the whole of this class. A prediction is made at one step and
  the label that shows whether it was right arrives at the next, so the classifier
  has to learn on the previous step's expectation with the current step's label,
  while reporting the new expectation.

  One classifier per step ahead. The one for step k maps an expectation to the
  label that arrived k steps after it was made, so it is taught by the
  expectation from k steps back and is asked about the newest one. That is why
  the last `steps` expectations are kept: they are the ones still waiting to be
  judged. A one-step predictor keeps exactly one and asks one classifier, which
  is what this class has always done.
  """
  let _memory: TemporalMemory
  let _classifiers: Array[SDRClassifier]
  let _steps: USize
  var _expected: Array[USize] val
  let _history: Array[Array[USize] val]
  var _last: Array[F64]

  new create(
    memory: TemporalMemory,
    categories: USize,
    learning_rate: F64 = 0.1,
    steps: USize = 1)
    ?
  =>
    """
    A predictor of what the memory expects, `steps` ahead. Fails when there is
    no category to predict into and when no step is asked for: a predictor of
    nothing has nothing to say.
    """
    if categories == 0 then error end
    if steps == 0 then error end

    _memory = memory
    _steps = steps

    let classifiers = Array[SDRClassifier](steps)
    var ahead: USize = 0
    while ahead < steps do
      classifiers.push(SDRClassifier(categories, memory.cells(), learning_rate)?)
      ahead = ahead + 1
    end
    _classifiers = classifiers

    let none: Array[USize] val = recover val Array[USize] end
    _expected = none
    _history = Array[Array[USize] val](steps)
    _last = Array[F64].init(1.0 / categories.f64(), categories)

  fun ref observe(
    columns: ReadSeq[USize],
    label: (USize | None),
    learn: Bool)
    : Array[F64] ?
  =>
    """
    Fold one step in and report the probability of each category for what comes
    next.

    `label` is what this step turned out to be. It is applied to the cells that
    were expected at the previous step, because those were the prediction being
    tested.
    """
    match label
    | let actual: USize =>
      if learn then _teach(actual)? end
    end

    let output = _memory.compute(columns, learn)?
    _expected = output.predictive_cells
    _remember(_expected)

    match _classifiers(0)?
    | let one: SDRClassifier =>
      _last = one.compute(_expected, None, false)?
    end

    _last

  fun ref _teach(actual: USize) ? =>
    """
    Give the label of this step to every classifier that was waiting for it: the
    one for step k is taught by the expectation made k steps ago, which is still
    in the history because it had not been judged yet.
    """
    var ahead: USize = 0
    while ahead < _steps do
      if ahead < _history.size() then
        let then_expected = _history((_history.size() - 1) - ahead)?
        if then_expected.size() > 0 then
          match _classifiers(ahead)?
          | let classifier: SDRClassifier =>
            classifier.compute(then_expected, actual, true)?
          end
        end
      end
      ahead = ahead + 1
    end

  fun ref _remember(expectation: Array[USize] val) =>
    """
    Keep the newest expectation and forget the ones no classifier is still
    waiting on.
    """
    _history.push(expectation)
    while _history.size() > _steps do
      try _history.shift()? end
    end

  fun expected(): Array[USize] val => _expected

  fun probabilities(): ReadSeq[F64] => _last

  fun best(): USize =>
    """
    The most likely category of the next step.
    """
    try _classifiers(0)?.best() else 0 end

  fun ref probabilities_at(step: USize): Array[F64] ? =>
    """
    The probability of each category `step` steps ahead, from the expectation
    the memory holds now.

    Steps are counted from one, and asking beyond what this predictor was built
    for is an error rather than a zero: a number nobody computed would look like
    a prediction with no confidence behind it.
    """
    if (step == 0) or (step > _steps) then error end
    _classifiers(step - 1)?.compute(_expected, None, false)?

  fun ref best_at(step: USize): USize ? =>
    """
    The likeliest category `step` steps ahead.
    """
    probabilities_at(step)?
    _classifiers(step - 1)?.best()
