use "../../htm"

primitive Cycle
  """
  Ten patterns of ten nodes each, a hundred nodes of eight cells, and a pooler
  whose settings the study changes one at a time.
  """
  fun of(index: USize): Array[USize] =>
    let columns = Array[USize](10)
    let start = (index % 10) * 10
    var column: USize = start
    while column < (start + 10) do
      columns.push(column)
      column = column + 1
    end
    columns

  fun config(
    pooling: Bool,
    window: USize,
    inference: USize,
    learning: USize): TemporalPoolerConfig val ?
  =>
    TemporalPoolerConfig(
      where
        columns' = 100,
        cells_per_column' = 8,
        activation_threshold' = 8,
        min_threshold' = 10,
        new_synapse_count' = 10,
        pooling' = pooling,
        initial_permanence' = 0.5,
        connected_threshold' = 0.5,
        permanence_increment' = 0.1,
        permanence_decrement' = 0.0,
        permanence_max' = 1.0,
        global_decay' = 0.0,
        update_window' = window,
        pam_length' = 10,
        max_inference_backtrack' = inference,
        max_learning_backtrack' = learning,
        max_segment_age' = 100000,
        max_sequence_length' = 32,
        max_segments_per_cell' = 0,
        max_synapses_per_segment' = 0)?

  fun learn_cycle(subject: TemporalPooler, passes: USize) ? =>
    """
    The cycle as a cycle: no reset between the patterns, so each follows the one
    before it and the first follows the tenth.
    """
    subject.reset()
    var step: USize = 0
    while step < passes do
      subject.compute(of(step), true, false)?
      step = step + 1
    end
    subject.reset()

  fun learn_branches(subject: TemporalPooler, passes: USize) ? =>
    """
    Two sequences that share a pattern: 0-1-2-3-4, and 2-8-9.
    """
    subject.reset()
    var pass: USize = 0
    while pass < passes do
      var index: USize = 0
      while index < 5 do
        subject.compute(of(index), true, false)?
        index = index + 1
      end

      subject.reset()
      subject.compute(of(2), true, false)?
      subject.compute(of(8), true, false)?
      subject.compute(of(9), true, false)?

      pass = pass + 1
    end

actor Main
  """
  What the pooler's settings are worth, measured on two streams.

  The first is a cycle of ten patterns, followed after sixty passes of teaching.
  The settings change how much the pooler says - pooling names the pattern after
  the next one too, and a longer window names more of the cycle again - and what
  it costs to remember: segments.

  The second is two sequences that share a pattern, followed into an input only
  the other one contains. What the re-play changes there is not what is
  predicted: it is the state the pooler is in, ten cells rather than the
  eighty a burst turns on.

  Nothing here reads a clock, so the numbers are the same on every machine.

  Expect pooling to name more of the cycle and to grow more segments, and the
  re-play to buy a precise state rather than a longer forecast.
  """
  new create(env: Env) =>
    try
      _cycle(env)?
      env.out.print("")
      _branches(env)?
      _conclusion(env)
      env.exitcode(0)
    else
      env.out.print("the study failed")
      env.exitcode(1)
    end

  fun _cycle(env: Env) ? =>
    """
    A cycle of ten patterns, followed after sixty passes of teaching, under
    three sets of settings.
    """
    env.out.print("a cycle of ten patterns, taught sixty times")
    env.out.print("settings            segments  named per step")

    _cycle_row(env, "plain", false, 1)?
    _cycle_row(env, "pooling, window 1", true, 1)?
    _cycle_row(env, "pooling, window 5", true, 5)?

  fun _cycle_row(
    env: Env,
    label: String,
    pooling: Bool,
    window: USize)
  ?
  =>
    let pooler = TemporalPooler(Cycle.config(pooling, window, 10, 5)?, 7)
    Cycle.learn_cycle(pooler, 60)?

    env.out.print(_padded(label, 20)
      + _padded(pooler.segments().string(), 10)
      + (_named_over_a_cycle(pooler)? / 10).string())

  fun _named_over_a_cycle(pooler: TemporalPooler): USize ? =>
    var named: USize = 0
    var step: USize = 0
    while step < 10 do
      pooler.compute(Cycle.of(step), false, true)?
      named = named + pooler.predicted_columns().size()
      step = step + 1
    end
    named

  fun _branches(env: Env) ? =>
    """
    Two sequences that share a pattern, followed into an input only the other
    one contains, with the re-play on and off.
    """
    env.out.print("two sequences that share a pattern, followed into an input")
    env.out.print("only the other one contains")
    env.out.print("re-play window      active cells  named")

    _branch_row(env, "ten steps", 10)?
    _branch_row(env, "none", 0)?

  fun _branch_row(env: Env, label: String, inference: USize) ? =>
    let pooler = TemporalPooler(Cycle.config(false, 1, inference, 5)?, 7)
    Cycle.learn_branches(pooler, 10)?

    pooler.compute(Cycle.of(0), false, true)?
    pooler.compute(Cycle.of(1), false, true)?
    pooler.compute(Cycle.of(2), false, true)?

    // 8 continues the sequence that began two steps ago
    pooler.compute(Cycle.of(8), false, true)?

    env.out.print(_padded(label, 20)
      + _padded(pooler.active_cells().size().string(), 14)
      + pooler.predicted_columns().size().string())

  fun _conclusion(env: Env) =>
    env.out.print("")
    env.out.print("the re-play does not find more of the next pattern here - the")
    env.out.print("same ten nodes either way. What it keeps is the state: ten cells")
    env.out.print("rather than a burst of eighty, and a precise state is what a")
    env.out.print("pooled union is built from.")

  fun _padded(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
