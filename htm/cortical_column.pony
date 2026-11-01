use "collections"

actor CorticalColumn
  """
  One column, answering on its own.

  The synapses arrive validated: a column cannot be built with a connection past
  the end of the input, because an actor constructor cannot report that failure.
  The pooler settles the width first and hands over synapses that fit.
  """
  let _index: USize
  let _synapses: Array[Synapse] val
  let _threshold: F64

  new create(index: USize, synapses: Array[Synapse] val, threshold: F64) =>
    _index = index
    _synapses = synapses
    _threshold = threshold

  be consider(active: Array[Bool] val, ballot: BallotBox tag) =>
    """
    Report this column's overlap for the given input.
    """
    let overlap = Synapses.overlap(_synapses, active, _threshold)
    ballot.vote(Vote(_index, overlap.f64()))
