class val TemporalPoolerConfig
  """
  The shape of a CLA temporal pooler and how readily it commits to a prediction.

  A pooler is wider than a plain temporal memory, and the extra parameters are
  the ones that decide what a *sequence* is: `activation_threshold` is how many
  of a segment's connected synapses have to reach cells that were active for the
  segment to predict, `min_threshold` is how many have to reach them for the
  segment to be worth learning on, and `new_synapse_count` is how many synapses a
  segment wants to end up with.

  `pooling` is what makes this a CLA rather than a sequence memory: when it is
  on, a cell that is still predicted also learns from the step before, so that
  the pattern it settles on is a union of the sub-patterns seen in that context
  rather than one path through them. It is the sixth parameter because it is the
  one a caller is most likely to change.

  `update_window` is how many steps a queued segment update stays worth applying;
  the reference drops it to one when `pooling` is off, because without pooling
  there is nothing to re-apply it to.

  The two limits start the fixed-size mode, where a cell may hold at most
  `max_segments_per_cell` segments and a segment at most
  `max_synapses_per_segment` synapses, and resources are recycled instead of
  growing. Zero means no limit; setting one and not the other is refused, as is
  fixed size beside a global decay or an age limit, since both give back the
  memory the mode promises to bound.

  Two parameters of the reference are deliberately absent. `burnIn` is read
  nowhere in it, so carrying it here would be a promise nothing keeps; and the
  statistics and printing flags belong to the pages that print, not to the
  computation.
  """
  let columns: USize
  let cells_per_column: USize
  let activation_threshold: USize
  let min_threshold: USize
  let new_synapse_count: USize
  let pooling: Bool
  let initial_permanence: F64
  let connected_threshold: F64
  let permanence_increment: F64
  let permanence_decrement: F64
  let permanence_max: F64
  let global_decay: F64
  let update_window: USize
  let pam_length: USize
  let max_inference_backtrack: USize
  let max_learning_backtrack: USize
  let max_segment_age: USize
  let max_sequence_length: USize
  let max_segments_per_cell: USize
  let max_synapses_per_segment: USize

  new val create(
    columns': USize,
    cells_per_column': USize = 10,
    activation_threshold': USize = 12,
    min_threshold': USize = 8,
    new_synapse_count': USize = 15,
    pooling': Bool = false,
    initial_permanence': F64 = 0.11,
    connected_threshold': F64 = 0.5,
    permanence_increment': F64 = 0.1,
    permanence_decrement': F64 = 0.1,
    permanence_max': F64 = 1.0,
    global_decay': F64 = 0.1,
    update_window': USize = 5,
    pam_length': USize = 1,
    max_inference_backtrack': USize = 10,
    max_learning_backtrack': USize = 5,
    max_segment_age': USize = 100000,
    max_sequence_length': USize = 32,
    max_segments_per_cell': USize = 0,
    max_synapses_per_segment': USize = 0) ?
  =>
    """
    The defaults are the reference's. Fails when there is no population to
    predict with (`columns` or `cells_per_column` zero), when `pam_length` is
    zero - a checkpoint every zero steps is not a checkpoint - or when the
    fixed-size limits are half set or contradict the decay they are supposed to
    replace.
    """
    if columns' == 0 then error end
    if cells_per_column' == 0 then error end
    if pam_length' == 0 then error end

    let bounded_segments = max_segments_per_cell' > 0
    let bounded_synapses = max_synapses_per_segment' > 0
    if bounded_segments != bounded_synapses then error end

    if bounded_segments then
      if global_decay' != 0.0 then error end
      if max_segment_age' != 0 then error end
      if max_synapses_per_segment' < new_synapse_count' then error end
    end

    columns = columns'
    cells_per_column = cells_per_column'
    activation_threshold = activation_threshold'
    min_threshold = min_threshold'
    new_synapse_count = new_synapse_count'
    pooling = pooling'
    initial_permanence = initial_permanence'
    connected_threshold = connected_threshold'
    permanence_increment = permanence_increment'
    permanence_decrement = permanence_decrement'
    permanence_max = permanence_max'
    global_decay = global_decay'
    update_window = if pooling' then update_window' else 1 end
    pam_length = pam_length'
    max_inference_backtrack = max_inference_backtrack'
    max_learning_backtrack = max_learning_backtrack'
    max_segment_age = max_segment_age'
    max_sequence_length = max_sequence_length'
    max_segments_per_cell = max_segments_per_cell'
    max_synapses_per_segment = max_synapses_per_segment'

  fun cells(): USize =>
    """
    How many cells the whole population holds.
    """
    columns * cells_per_column

  fun cell_of(node: USize, offset: USize): USize =>
    """
    The name a cell is known by everywhere else: its column, then its position
    within the column, laid out the way the rest of the library lays cells out.
    """
    (node * cells_per_column) + offset

  fun node_of(cell: USize): USize =>
    """
    The column a named cell belongs to.
    """
    cell / cells_per_column

  fun offset_of(cell: USize): USize =>
    """
    A named cell's position within its column.
    """
    cell % cells_per_column

  fun fixed_size(): Bool =>
    """
    Whether cells and segments are bounded and recycled rather than allowed to
    grow.
    """
    max_segments_per_cell > 0
