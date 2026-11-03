// Ported from temporalMemory.go in htm-community/htm (MIT). See docs/sources.md.
class val TemporalMemoryParams
  """
  The shape of a temporal memory and how readily it predicts.

  `activation_threshold` is how many of a segment's connected synapses have to
  reach cells that were active for the segment to count as a prediction. With
  a small population one is enough; with a real one it wants to be well above
  one, or every segment predicts everything.
  """
  let columns: USize
  let cells_per_column: USize
  let activation_threshold: USize
  let connected_threshold: F64
  let initial_permanence: F64
  let permanence_increment: F64
  let permanence_decrement: F64
  let max_synapses: USize
  let max_segments_per_cell: USize

  new val create(
    columns': USize,
    cells_per_column': USize = 32,
    activation_threshold': USize = 13,
    connected_threshold': F64 = 0.5,
    initial_permanence': F64 = 0.5,
    permanence_increment': F64 = 0.1,
    permanence_decrement': F64 = 0.02,
    max_synapses': USize = 32,
    max_segments_per_cell': USize = 10)
  =>
    columns = columns'
    cells_per_column = cells_per_column'
    activation_threshold = activation_threshold'
    connected_threshold = connected_threshold'
    initial_permanence = initial_permanence'
    permanence_increment = permanence_increment'
    permanence_decrement = permanence_decrement'
    max_synapses = max_synapses'
    max_segments_per_cell = max_segments_per_cell'

  fun cells(): USize => columns * cells_per_column

  fun column_of(cell: USize): USize => cell / cells_per_column
