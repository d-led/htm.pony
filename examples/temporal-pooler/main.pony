use "../../htm"

primitive Sequence
  """
  Five patterns of ten nodes each, and the pooler that learns them: fifty
  nodes, two cells each, ten synapses to a segment, and no pooling.
  """
  fun of(index: USize): Array[USize] =>
    let columns = Array[USize](10)
    let start = index * 10
    var column: USize = start
    while column < (start + 10) do
      columns.push(column)
      column = column + 1
    end
    columns

  fun config(): TemporalPoolerConfig val ? =>
    TemporalPoolerConfig(
      50, 2,              // nodes, and cells in each
      8, 10, 10,          // activation threshold, min threshold, synapses wanted
      false,              // no pooling
      0.5, 0.5,           // initial and connection permanence
      0.1, 0.0, 1.0,      // permanence increment, decrement, ceiling
      0.0,                // no global decay
      1, 10,              // update window, pam length
      10, 5,              // the two backtrack windows
      100000,             // nothing is ever aged out
      32,                 // longest sequence worth naming
      0, 0)?              // no fixed-size limits

actor Main
  """
  A CLA temporal pooler learning that one pattern follows another.

  Five patterns are shown in order, ten times, each showing ending in a reset.
  Then the first is shown alone, and the pooler says what it expects next - and,
  when asked, what comes after that, and after that again, from the state that
  follows rather than from the input.

  The difference from the temporal memory example is the state a node settles
  on. A temporal memory bursts a node into all of its cells and learns from the
  step before; a pooler learns from the step before *that* while a cell is still
  being predicted, so what it ends up predicting is a union of the situations
  that led here rather than a single path through them.
  """
  new create(env: Env) =>
    try
      let pooler = TemporalPooler(Sequence.config()?, 7)

      var epoch: USize = 0
      while epoch < 10 do
        var index: USize = 0
        while index < 5 do
          pooler.compute(Sequence.of(index), true, false)?
          index = index + 1
        end
        pooler.reset()
        epoch = epoch + 1
      end

      env.out.print("taught five patterns, in order, ten times")
      env.out.print("  segments grown:  " + pooler.segments().string())
      env.out.print("")

      pooler.compute(Sequence.of(0), false, true)?
      env.out.print("showing pattern 0 alone")
      env.out.print("  active cells:    " + _cells(pooler.active_cells()))
      env.out.print("  predicts nodes:  " + _cells(pooler.predicted_columns()))
      env.out.print("")

      env.out.print("asking what follows, three steps out")
      let forecast = pooler.predict(3)?
      var step: USize = 0
      while step < forecast.size() do
        env.out.print(
          "  step " + (step + 1).string() + ":  " +
            _cells(_confident(forecast(step)?)))
        step = step + 1
      end
      env.out.print("")

      env.out.print("asking did not decide anything: the pooler still predicts")
      env.out.print("  " + _cells(pooler.predicted_columns()))
      env.out.print("")
      env.out.print("each step of the forecast is the pattern that follows the one")
      env.out.print("before it, because that is the only continuation it was taught")

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _cells(values: ReadSeq[USize]): String =>
    var text: String = "["
    for value in values.values() do
      if text.size() > 1 then text = text + ", " end
      text = text + value.string()
    end
    text + "]"

  fun _confident(confidences: ReadSeq[F64]): Array[USize] =>
    """
    The nodes a forecast says something about, in node order.
    """
    let found = Array[USize]
    var node: USize = 0
    while node < confidences.size() do
      try
        if confidences(node)? > 0.0 then found.push(node) end
      end
      node = node + 1
    end
    found
