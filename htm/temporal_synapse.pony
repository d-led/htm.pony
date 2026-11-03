// Ported from temporalMemoryConnections.go in htm-community/htm (MIT).
// See docs/sources.md.
class TemporalSynapse
  """
  A connection from a segment to the cell that was active when the segment
  learned it.

  Unlike a proximal synapse, which reaches an input bit, this one reaches
  another cell: that is what lets a column remember what came before it.
  """
  let source: USize
  var permanence: F64

  new create(source': USize, permanence': F64) =>
    source = source'
    permanence = permanence'

  fun connected(threshold: F64): Bool => permanence >= threshold
