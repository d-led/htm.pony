class SDRClassifier
  """
  Turns an active set of cells into a probability for each category.

  The temporal memory says which cells it expects. This says what those cells
  have meant so far: each input bit carries one weight per category, a category's
  score is the sum of the weights of the bits that are active, and the scores
  become probabilities through a softmax.

  It is deliberately one layer and no more. The representation already does the
  work - the memory's cells are the feature - so the classifier only has to learn
  which feature means which label.

  Learning is the same pass as inference: given the category that turned out to
  be true, every active bit moves its weight towards it and away from the others.
  """
  let categories: USize
  let inputs: USize
  let learning_rate: F64
  let _weights: Array[Array[F64]]
  var _last: Array[F64]

  new create(categories': USize, inputs': USize, learning_rate': F64 = 0.1) ? =>
    if categories' == 0 then error end
    if inputs' == 0 then error end

    categories = categories'
    inputs = inputs'
    learning_rate = learning_rate'

    let weights = Array[Array[F64]](categories')
    var category: USize = 0
    while category < categories' do
      weights.push(Array[F64].init(0.0, inputs'))
      category = category + 1
    end

    _weights = weights
    _last = Array[F64].init(1.0 / categories'.f64(), categories')

  fun ref compute(
    active: ReadSeq[USize],
    category: (USize | None),
    learn: Bool)
    : Array[F64] ?
  =>
    """
    The probability of each category given the active inputs, and, when a
    category is supplied and learning is on, one step of learning towards it.
    """
    let likely = _softmax(active)?

    match category
    | let actual: USize =>
      if actual >= categories then error end
      if learn then _learn(active, actual, likely)? end
    end

    _last = likely
    _last

  fun best(): USize =>
    """
    The most likely category of the last call.
    """
    var chosen: USize = 0
    var index: USize = 0
    while index < _last.size() do
      try
        if _last(index)? > _last(chosen)? then chosen = index end
      end
      index = index + 1
    end
    chosen

  fun probabilities(): ReadSeq[F64] => _last

  fun _softmax(active: ReadSeq[USize]): Array[F64] ? =>
    let scores = Array[F64].init(0.0, categories)

    for index in active.values() do
      if index >= inputs then error end
      var category: USize = 0
      while category < categories do
        scores(category)? = scores(category)? + _weights(category)?(index)?
        category = category + 1
      end
    end

    let highest = _highest(scores)
    var total: F64 = 0.0
    var category: USize = 0
    while category < categories do
      let raised = (scores(category)? - highest).exp()
      scores(category)? = raised
      total = total + raised
      category = category + 1
    end

    category = 0
    while category < categories do
      scores(category)? = scores(category)? / total
      category = category + 1
    end

    scores

  fun ref _learn(active: ReadSeq[USize], actual: USize, likely: Array[F64]) ? =>
    for index in active.values() do
      var category: USize = 0
      while category < categories do
        let target: F64 = if category == actual then 1.0 else 0.0 end
        let delta = (target - likely(category)?) * learning_rate
        let weights = _weights(category)?
        weights(index)? = weights(index)? + delta
        category = category + 1
      end
    end

  fun _highest(scores: ReadSeq[F64]): F64 =>
    var highest: F64 = -1000000.0
    for score in scores.values() do
      if score > highest then highest = score end
    end
    highest
