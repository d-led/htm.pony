use "collections"

class Column
  """
  A cortical column: the input bits it reaches, and how strongly it believes in
  each of them.

  `overlap` is the column's claim on the current input - how many of the bits it
  is connected to are active. Inhibition then decides which claims are strong
  enough to become the representation.
  """
  embed synapses: Array[Synapse]

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
    var count: USize = 0

    for synapse in synapses.values() do
      if not synapse.connected(connection_threshold) then continue end
      if active(synapse.input)? then
        count = count + 1
      end
    end

    count
