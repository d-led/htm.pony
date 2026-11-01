class StreamingAnomalyDetector
  """
  One input at a time, one anomaly score back.

  The spatial pooler turns each input into columns, the temporal memory learns
  the order those columns arrive in, and the score is the share of this step's
  columns that the memory did not expect. Learning and scoring happen in the same
  pass, which is what makes it work on a stream rather than on a training set:
  there is no separate phase, and the model is never frozen.

  The score is noisy by nature. A single high value can be a genuinely strange
  input or a column the pooler happened to light up differently; what carries
  meaning is a run of them, or a distribution that shifts.
  """
  let _pooler: SpatialPooler
  let _memory: TemporalMemory
  var _last: F64 = 0.0

  new create(pooler: SpatialPooler, memory: TemporalMemory) =>
    _pooler = pooler
    _memory = memory

  fun ref observe(input: ReadSeq[Bool], learn: Bool = true): F64 ? =>
    """
    Fold one input into the model and report how surprising it was.
    """
    let columns = _pooler.compute(input)?
    let output = _memory.compute(columns, learn)?
    _last = output.anomaly(_memory.params)
    _last

  fun last(): F64 => _last
