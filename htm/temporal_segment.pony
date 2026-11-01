class TemporalSegment
  """
  What one cell remembers about the situation that came before it.

  A segment holds synapses onto other cells. It is active when enough of the
  cells it reaches were active at the previous step, and a cell with an active
  segment is the memory's prediction: this cell expects to be part of what comes
  next.

  A cell can hold several segments. One cell in one column cannot distinguish
  "after A" from "after Q" with a single segment, but two segments can.
  """
  let owner: USize
  var synapses: Array[TemporalSynapse]
  var last_used: U64 = 0

  new create(owner': USize) =>
    owner = owner'
    synapses = Array[TemporalSynapse]

  fun matching(previous: ReadSeq[Bool], threshold: F64): USize =>
    """
    How many of this segment's connected synapses reach cells that were active
    at the previous step.
    """
    var count: USize = 0
    for synapse in synapses.values() do
      if not synapse.connected(threshold) then continue end
      try
        if previous(synapse.source)? then count = count + 1 end
      end
    end
    count

  fun ref strengthen(previous: ReadSeq[Bool], increment: F64, decrement: F64) =>
    """
    Move every synapse towards or away from connection, depending on whether
    the cell it reaches was active.
    """
    for synapse in synapses.values() do
      if _was_active(previous, synapse.source) then
        synapse.permanence = _clipped(synapse.permanence + increment)
      else
        synapse.permanence = _clipped(synapse.permanence - decrement)
      end
    end

  fun ref weaken(previous: ReadSeq[Bool], decrement: F64) =>
    """
    Move towards disconnection every synapse that reaches a cell which was
    active when this segment predicted and did not become active afterwards.

    Without this a segment keeps the synapses it was born with forever, including
    the ones pointing at cells that never fire again, and the orphaned synapses
    hold its match count down.
    """
    for synapse in synapses.values() do
      if _was_active(previous, synapse.source) then
        synapse.permanence = _clipped(synapse.permanence - decrement)
      end
    end

  fun ref connect_to(cells: ReadSeq[USize], permanence: F64, limit: USize) =>
    """
    Grow synapses to cells this segment does not already reach, up to `limit`.
    """
    for cell in cells.values() do
      if synapses.size() >= limit then return end
      if not _reaches(cell) then
        synapses.push(TemporalSynapse(cell, permanence))
      end
    end

  fun ref prune() =>
    """
    Forget synapses that have decayed to nothing, so a segment does not carry
    dead weight it can never revive.
    """
    var kept = Array[TemporalSynapse](synapses.size())
    for synapse in synapses.values() do
      if synapse.permanence > 0.0 then kept.push(synapse) end
    end
    synapses = kept

  fun _reaches(cell: USize): Bool =>
    for synapse in synapses.values() do
      if synapse.source == cell then return true end
    end
    false

  fun _was_active(previous: ReadSeq[Bool], cell: USize): Bool =>
    try previous(cell)? else false end

  fun _clipped(permanence: F64): F64 =>
    if permanence < 0.0 then 0.0
    elseif permanence > 1.0 then 1.0
    else permanence end
