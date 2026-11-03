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
      100, 8,             // nodes, and cells in each
      8, 10, 10,          // activation threshold, min threshold, synapses wanted
      pooling,
      0.5, 0.5,
      0.1, 0.0, 1.0,
      0.0,
      window, 10,         // update window, pam length
      inference, learning,
      100000,
      32,
      0, 0)?

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
  """
  new create(env: Env) =>
    try
      env.out.print("a cycle of ten patterns, taught sixty times")
      env.out.print("settings            segments  named per step")

      var which: USize = 0
      while which < 3 do
        let pooling = which > 0
        let window: USize = if which == 2 then 5 else 1 end
        let pooler = TemporalPooler(Cycle.config(pooling, window, 10, 5)?, 7)
        Cycle.learn_cycle(pooler, 60)?

        var named: USize = 0
        var step: USize = 0
        while step < 10 do
          pooler.compute(Cycle.of(step), false, true)?
          named = named + pooler.predicted_columns().size()
          step = step + 1
        end

        let label: String =
          if which == 0 then "plain" 
          elseif which == 1 then "pooling, window 1"
          else "pooling, window 5"
          end

        env.out.print(_padded(label, 20) + _padded(pooler.segments().string(), 10) +
          (named / 10).string())
        which = which + 1
      end

      env.out.print("")
      env.out.print("two sequences that share a pattern, followed into an input")
      env.out.print("only the other one contains")
      env.out.print("re-play window      active cells  named")

      var inference: USize = 10
      var round: USize = 0
      while round < 2 do
        let pooler = TemporalPooler(Cycle.config(false, 1, inference, 5)?, 7)
        Cycle.learn_branches(pooler, 10)?

        pooler.compute(Cycle.of(0), false, true)?
        pooler.compute(Cycle.of(1), false, true)?
        pooler.compute(Cycle.of(2), false, true)?

        // 8 continues the sequence that began two steps ago
        pooler.compute(Cycle.of(8), false, true)?

        let label: String = if inference == 0 then "none" else "ten steps" end
        env.out.print(
          _padded(label, 20) +
            _padded(pooler.active_cells().size().string(), 14) +
            pooler.predicted_columns().size().string())

        inference = 0
        round = round + 1
      end

      env.out.print("")
      env.out.print("the re-play does not find more of the next pattern here - the")
      env.out.print("same ten nodes either way. What it keeps is the state: ten cells")
      env.out.print("rather than a burst of eighty, and a precise state is what a")
      env.out.print("pooled union is built from.")

      env.exitcode(0)
    else
      env.out.print("the study failed")
      env.exitcode(1)
    end

  fun _padded(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
