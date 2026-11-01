use "../../htm"

actor Main
  """
  A temporal memory learning that one column follows another.

  Two columns are shown in turn, a few times, with learning on. Then the first
  is shown alone and the memory says what it expects next.
  """
  new create(env: Env) =>
    try
      let memory = TemporalMemory(TemporalMemoryParams(4, 4, 1, 0.5, 0.5, 0.1, 0.02, 8, 4))

      env.out.print("teaching: column 0 then column 1")

      var round: USize = 0
      while round < 3 do
        memory.compute([0], true)?
        memory.compute([1], true)?
        round = round + 1
      end

      let after_learning = memory.compute([0], false)?
      env.out.print("")
      env.out.print("showing column 0 alone")
      env.out.print("  active cells:      " + _cells(after_learning.active_cells))
      env.out.print("  bursts:            " + _cells(after_learning.bursting_columns) + " (columns)")
      env.out.print("  predicts columns:  " + _cells(after_learning.predicted_columns(memory.params)))

      let predicted = memory.compute([1], false)?
      env.out.print("")
      env.out.print("showing column 1, which was predicted")
      env.out.print("  active cells:      " + _cells(predicted.active_cells))
      env.out.print("  bursts:            " + _cells(predicted.bursting_columns) + " (columns)")
      env.out.print("")
      env.out.print("a predicted column activates only the cells that were predicted,")
      env.out.print("so it no longer bursts")

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
