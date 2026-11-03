use "../../htm"

primitive Branches
  """
  Two sequences that share a pattern: 0-1-2-3-4 and 2-8-9. The pooler has room
  for ten patterns, so the second sequence is a different path out of 2.
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
      where
        columns' = 100,
        cells_per_column' = 2,
        activation_threshold' = 8,
        min_threshold' = 10,
        new_synapse_count' = 10,
        pooling' = false,
        initial_permanence' = 0.5,
        connected_threshold' = 0.5,
        permanence_increment' = 0.1,
        permanence_decrement' = 0.0,
        permanence_max' = 1.0,
        global_decay' = 0.0,
        update_window' = 1,
        pam_length' = 10,
        max_inference_backtrack' = 10,
        max_learning_backtrack' = 5,
        max_segment_age' = 100000,
        max_sequence_length' = 32,
        max_segments_per_cell' = 0,
        max_synapses_per_segment' = 0)?

actor Main
  """
  A pooler that has lost the sequence it was following, and finds it again.

  Following 0-1-2-3-4, the pooler predicts 3. What arrives is 8, which it did
  not predict and which is not a continuation of what it was following - so
  without looking back it would burst every node of 8 and start again.

  Instead it re-plays the recent inputs on the assumption that the sequence
  began further back than it thought. Starting from 2 explains the input: 2-8-9
  is a sequence it knows. So 8 is activated as a prediction rather than a burst,
  and 9 is predicted next.

  The two numbers to read are the active cells. Twenty would be a burst - every
  cell of all ten nodes. Ten is one cell a node, which is what a predicted node
  looks like, and it is the difference between giving up on the sequence and
  finding it.

  Expect ten active cells on the step after the break, not twenty, and 9 named
  as the next prediction.
  """
  new create(env: Env) =>
    try
      let pooler = TemporalPooler(Branches.config()?, 7)
      _teach(pooler, env)?
      _follow(pooler, env)?
      _recover(pooler, env)?
      _conclusion(env)
      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _teach(pooler: TemporalPooler, env: Env) ? =>
    """
    The long sequence, then the branch out of it, ten times over.
    """
    var epoch: USize = 0
    while epoch < 10 do
      _long_sequence(pooler)?
      pooler.reset()
      _branch(pooler)?
      pooler.reset()
      epoch = epoch + 1
    end

    env.out.print("taught two sequences that share a pattern:")
    env.out.print("  0 1 2 3 4, and 2 8 9")
    env.out.print("")

  fun _long_sequence(pooler: TemporalPooler) ? =>
    var index: USize = 0
    while index < 5 do
      pooler.compute(Branches.of(index), true, false)?
      index = index + 1
    end

  fun _branch(pooler: TemporalPooler) ? =>
    pooler.compute(Branches.of(2), true, false)?
    pooler.compute(Branches.of(8), true, false)?
    pooler.compute(Branches.of(9), true, false)?

  fun _follow(pooler: TemporalPooler, env: Env) ? =>
    """
    The start of the long sequence, watched rather than taught: 2 is followed by
    3, so 3 is what the pooler expects.
    """
    pooler.compute(Branches.of(0), false, true)?
    pooler.compute(Branches.of(1), false, true)?
    pooler.compute(Branches.of(2), false, true)?
    env.out.print("following 0 1 2, it predicts")
    env.out.print("  " + _cells(pooler.predicted_columns()))
    env.out.print("")

  fun _recover(pooler: TemporalPooler, env: Env) ? =>
    """
    An input it did not predict, which looks back far enough to explain.
    """
    pooler.compute(Branches.of(8), false, true)?
    env.out.print("what arrives is 8, which was not predicted")
    env.out.print("  active cells:    " + _cells(pooler.active_cells()))
    env.out.print("  that is " + pooler.active_cells().size().string()
      + " cells, one a node rather than a burst")
    env.out.print("  and it predicts: " + _cells(pooler.predicted_columns()))
    env.out.print("")

  fun _conclusion(env: Env) =>
    env.out.print("so it found the sequence 2 8 9 that began two steps ago, and")
    env.out.print("carried on from there instead of starting again")

  fun _cells(values: ReadSeq[USize]): String =>
    var text: String = "["
    for value in values.values() do
      if text.size() > 1 then text = text + ", " end
      text = text + value.string()
    end
    text + "]"
