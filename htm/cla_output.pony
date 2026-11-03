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
