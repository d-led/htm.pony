// Follows spatialPooler.go in htm-community/htm (MIT) with this repository's
// structure. See docs/sources.md.
use "collections"

primitive Synapses
  """
  Overlap arithmetic that stays total, so a caller which cannot raise - an actor
  constructor cannot fail - is not handed a partial function.
  """

  fun overlap(synapses: ReadSeq[Synapse], active: ReadSeq[Bool], threshold: F64): USize =>
    """
    How many of the connected synapses see an active input bit. A synapse whose
    input lies outside the active vector is skipped.
    """
    var count: USize = 0
    let width = active.size()

    for synapse in synapses.values() do
      if not synapse.connected(threshold) then continue end
      if synapse.input < width then
        try
          if active(synapse.input)? then
            count = count + 1
          end
        end
      end
    end

    count

  fun fits(synapses: ReadSeq[Synapse], width: USize): Bool =>
    """
    Whether every synapse of a column reaches inside an input of this width.
    """
    for synapse in synapses.values() do
      if synapse.input >= width then return false end
    end
    true

  fun connected(synapses: ReadSeq[Synapse], threshold: F64): USize =>
    """
    How many of a column's synapses are strong enough to count.
    """
    var count: USize = 0
    for synapse in synapses.values() do
      if synapse.connected(threshold) then
        count = count + 1
      end
    end
    count
