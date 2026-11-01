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
  """
  let _memory: TemporalMemory
  let _classifier: SDRClassifier
  var _expected: Array[USize] val
  var _last: Array[F64]

  new create(
    memory: TemporalMemory,
    categories: USize,
    learning_rate: F64 = 0.1)
    ?
  =>
    if categories == 0 then error end

    _memory = memory
    _classifier = SDRClassifier(categories, memory.cells(), learning_rate)?

    let none: Array[USize] val = recover val Array[USize] end
    _expected = none
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
      if learn and (_expected.size() > 0) then
        _classifier.compute(_expected, actual, true)?
      end
    end

    let output = _memory.compute(columns, learn)?
    _expected = output.predictive_cells
    _last = _classifier.compute(_expected, None, false)?
    _last

  fun expected(): Array[USize] val => _expected

  fun probabilities(): ReadSeq[F64] => _last

  fun best(): USize => _classifier.best()
