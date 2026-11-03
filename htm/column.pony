// Follows spatialPooler.go in htm-community/htm (MIT) with this repository's
// structure: a column is an object with synapses, not a row of a matrix.
use "collections"

class Column
  """
  A cortical column: the input bits it reaches, and how strongly it believes in
  each of them.

  `overlap` is the column's claim on the current input - how many of the bits it
  is connected to are active. Inhibition then decides which claims are strong
  enough to become the representation.

  The synapses are the column's receptive field, chosen once at wiring time and
  then kept: learning moves their permanences, it does not choose new inputs. A
  permanence of zero is a connection the column has let go of without forgetting
  where it used to look.
  """
  var synapses: Array[Synapse]

  new create(synapses': ReadSeq[Synapse]) =>
    synapses = Array[Synapse](synapses'.size())
    for synapse in synapses'.values() do
      synapses.push(synapse)
    end

  fun overlap(active: ReadSeq[Bool], connection_threshold: F64): USize ? =>
    """
    How many of this column's connected synapses see an active input bit.

    Fails when a synapse reaches outside the input: the caller owns the input
    width, so a column that does not fit it is a wiring error, not an overlap.
    """
    if not Synapses.fits(synapses, active.size()) then error end
    Synapses.overlap(synapses, active, connection_threshold)

  fun ref adapt(active: ReadSeq[Bool], strengthen_by: F64, weaken_by: F64) =>
    """
    Move each permanence towards the input it sees or away from it: a synapse
    whose bit is on is strengthened, every other one is weakened.

    This is the whole of what a column learns. Nothing here decides *whether*
    the column should learn - inhibition decides that - so a column can be
    adapted to an input it did not win with, which is what a boosted column
    needs.
    """
    var index: USize = 0
    while index < synapses.size() do
      try
        let synapse = synapses(index)?
        let change = if _active(synapse.input, active) then strengthen_by else -weaken_by end
        synapses(index)? = Synapse(synapse.input, _clamped(synapse.permanence + change))
      end
      index = index + 1
    end

  fun ref ensure_connected(stimulus_threshold: USize, connection_threshold: F64, stride: F64) =>
    """
    Keep raising every permanence until enough synapses are connected.

    A column needs a minimum number of connected synapses before inhibition will
    ever hear it, and a column wired shy of that minimum could never win and so
    could never learn. Raising the whole receptive field together keeps the shape
    the seed gave it.
    """
    if stimulus_threshold > synapses.size() then return end
    if stride <= 0.0 then return end

    while Synapses.connected(synapses, connection_threshold) < stimulus_threshold do
      strengthen_all(stride)
    end

  fun ref trim(below: F64) =>
    """
    Let go of the connections too weak to matter.

    The synapse stays, with a permanence of zero, so the column keeps its
    receptive field and a later boost can bring the connection back.
    """
    var index: USize = 0
    while index < synapses.size() do
      try
        let synapse = synapses(index)?
        if synapse.permanence <= below then
          synapses(index)? = Synapse(synapse.input, 0.0)
        end
      end
      index = index + 1
    end

  fun ref strengthen_all(by: F64) =>
    """
    Raise every permanence of the receptive field, staying inside [0, 1].
    """
    var index: USize = 0
    while index < synapses.size() do
      try
        let synapse = synapses(index)?
        synapses(index)? = Synapse(synapse.input, _clamped(synapse.permanence + by))
      end
      index = index + 1
    end

  fun _active(input: USize, active: ReadSeq[Bool]): Bool =>
    if input >= active.size() then return false end
    try active(input)? else false end

  fun _clamped(permanence: F64): F64 =>
    if permanence < 0.0 then
      0.0
    elseif permanence > 1.0 then
      1.0
    else
      permanence
    end
