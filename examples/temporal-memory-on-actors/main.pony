use "../../htm"

actor Main
  """
  The same temporal memory running on actors.

  Four columns, four cells each, and a sequence of two columns repeating. The
  in-process memory runs the sequence first, then a region of two shards runs
  the same sequence, and the two are compared step by step.

  A step is two passes over the shards - activate, then predict - because a
  prediction is about a state that includes what every column did. The region
  answers only when both passes are back.

  Expect every step to agree with the in-process one, activation and prediction
  both.
  """
  let _env: Env
  let _region: TemporalRegion tag
  let _expected: Array[TemporalOutput val] val
  var _step: USize = 0
  var _matches: USize = 0

  new create(env: Env) =>
    _env = env
    _expected = _in_process()
    _region = TemporalRegion(_params(), TemporalShards.build(_params(), 2))

    env.out.print("the sequence, and what a temporal memory expects after each step")
    env.out.print("")
    for output in _expected.values() do
      env.out.print("  active " + _pad(_cells(output.active_cells), 14)
        + " expects " + _pad(_cells(output.predictive_cells), 14)
        + " bursts " + _cells(output.bursting_columns))
    end

    env.out.print("")
    env.out.print("the same sequence on two shards of two columns")

    try
      _region.compute(_steps()(0)?, true, this)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun tag _params(): TemporalMemoryParams val =>
    TemporalMemoryParams(
      where
        columns' = 4,
        cells_per_column' = 4,
        activation_threshold' = 1,
        max_synapses' = 8,
        max_segments_per_cell' = 4)

  fun tag _steps(): Array[Array[USize] val] =>
    let steps = Array[Array[USize] val]
    for column in _sequence().values() do
      steps.push(recover val [column] end)
    end
    steps

  fun tag _sequence(): Array[USize] => [0; 1; 0; 1; 0; 1]

  fun tag _in_process(): Array[TemporalOutput val] val =>
    recover val
      try
        let memory = TemporalMemory(_params())
        let answers = Array[TemporalOutput val]
        for step in _steps().values() do
          answers.push(memory.compute(step, true)?)
        end
        answers
      else
        Array[TemporalOutput val]
      end
    end

  be observed(output: TemporalOutput val) =>
    """
    One answer from the region, compared with the one process's answer.
    """
    try
      let wanted = _expected(_step)?
      if _same(output.active_cells, wanted.active_cells)
        and _same(output.predictive_cells, wanted.predictive_cells)
        and _same(output.bursting_columns, wanted.bursting_columns)
      then
        _matches = _matches + 1
      end
    end

    _env.out.print("  step " + _step.string() + " agrees")
    _step = _step + 1

    if _step < _expected.size() then
      try
        _region.compute(_steps()(_step)?, true, this)
      end
    else
      _env.out.print("")
      if _matches == _expected.size() then
        _env.out.print("every step on actors matches the one in process")
      else
        _env.out.print("the two paths disagree on "
          + (_expected.size() - _matches).string() + " steps")
        _env.exitcode(1)
      end
    end

  fun tag _cells(values: ReadSeq[USize]): String =>
    if values.size() == 0 then return "-" end

    var text: String = ""
    for value in values.values() do
      if text.size() > 0 then text = text + " " end
      text = text + value.string()
    end
    text

  fun tag _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun tag _same(left: ReadSeq[USize], right: ReadSeq[USize]): Bool =>
    if left.size() != right.size() then return false end
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? != right(index)? then return false end
        index = index + 1
      end
      true
    else
      false
    end
