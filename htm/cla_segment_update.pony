// Follows segmentUpdate.go in htm-community/htm (MIT) with this repository's
// structure. See docs/sources.md.
class ClaSegmentUpdate
  """
  A proposal to change a segment, made at one step and applied at a later one.

  A pooler predicts forward: at the step it predicts, it notes which of a
  segment's synapses reach cells that are on, and which cells it ought to reach
  but does not. It cannot apply that yet, because whether the prediction was
  right is only known when the next input arrives - a segment that predicted a
  cell which then stays dark has to be weakened, and one that predicted well has
  to be strengthened. So the proposal waits in the pooler's queue for the step
  that can judge it.

  Two lists rather than one: `strengthen` holds positions of synapses the
  segment already has, `reach` holds cells it does not reach yet. When there is
  no segment at all - the cell has to learn a new situation from nothing - both
  the segment and every synapse are new, so `strengthen` is empty and `reach`
  carries the whole situation.
  """
  let column: USize
  let offset: USize
  let segment: (ClaSegment | None)
  let strengthen: Array[USize]
  let reach: Array[USize]
  let when: U64

  new create(
    column': USize,
    offset': USize,
    segment': (ClaSegment | None),
    strengthen': Array[USize],
    reach': Array[USize],
    when': U64)
  =>
    column = column'
    offset = offset'
    segment = segment'
    strengthen = strengthen'
    reach = reach'
    when = when'

  fun proposed(): Bool =>
    """
    Whether there is anything to do. An update that neither strengthens an
    existing synapse nor reaches a new cell is dropped rather than queued: it
    would expire without ever changing anything.
    """
    (strengthen.size() > 0) or (reach.size() > 0)
