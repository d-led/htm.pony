class val ClaOutput
  """
  What one step of a CLA pooler produced.

  `output_cells` is the step's answer, the same set `TemporalPooler.compute`
  hands back: every cell that is active or predicted. `active_cells` are the
  cells that are active now, `predictive_cells` the ones the pooler expects at
  the next step, and `predicted_nodes` the nodes those predictions belong to.
  `node_confidences` is how much of the step's confidence each node carries, so
  an answer says how sure the pooler is and not only what it chose.

  A node is named rather than a column because a pooler's population is nodes of
  cells, and a consumer that wants to know what is coming next wants the node
  names it gave in.

  `bursting_nodes` and `anomaly` are the reading the temporal memory's output
  offers, in the pooler's terms: a node that had to light up every cell is a node
  that had no prediction into it.
  """
  let output_cells: Array[USize] val
  let active_cells: Array[USize] val
  let predictive_cells: Array[USize] val
  let predicted_nodes: Array[USize] val
  let node_confidences: Array[F64] val

  new val create(
    output_cells': Array[USize] val,
    active_cells': Array[USize] val,
    predictive_cells': Array[USize] val,
    predicted_nodes': Array[USize] val,
    node_confidences': Array[F64] val)
  =>
    output_cells = output_cells'
    active_cells = active_cells'
    predictive_cells = predictive_cells'
    predicted_nodes = predicted_nodes'
    node_confidences = node_confidences'

  fun bursting_nodes(config: TemporalPoolerConfig val): Array[USize] val =>
    """
    The nodes that lit up every one of their cells.

    A pooler activates the cells it predicted, and only a node it had no
    prediction into gets all of them. So this is the pooler's answer to "which
    nodes surprised me", node by node.
    """
    let counted = _active_per_node(config)
    let bursting: Array[USize] iso = recover iso Array[USize] end

    for (node, cells) in counted.pairs() do
      if cells == config.cells_per_column then bursting.push(node) end
    end

    bursting

  fun anomaly(config: TemporalPoolerConfig val): F64 =>
    """
    The share of the active nodes the pooler had no prediction for.

    The same reading `TemporalOutput.anomaly` gives for a temporal memory: a node
    that bursts is a prediction that failed, so zero means everything that
    happened was expected and one means nothing was. It is a property of this
    step alone; a run of them is what tells you whether something is wrong.

    A node nobody activated counts for nothing, and a step with no active node is
    zero rather than one: nothing happened, so nothing was surprising.
    """
    let counted = _active_per_node(config)
    var active: USize = 0
    var bursting: USize = 0

    for cells in counted.values() do
      if cells > 0 then
        active = active + 1
        if cells == config.cells_per_column then bursting = bursting + 1 end
      end
    end

    if active == 0 then return 0.0 end
    bursting.f64() / active.f64()

  fun _active_per_node(config: TemporalPoolerConfig val): Array[USize] val =>
    """
    How many of each node's cells are active, in node order.
    """
    let counted: Array[USize] iso = recover iso Array[USize] end
    var node: USize = 0
    while node < config.columns do
      counted.push(0)
      node = node + 1
    end

    for cell in active_cells.values() do
      let active_node = config.node_of(cell)
      try counted(active_node)? = counted(active_node)? + 1 end
    end

    counted
