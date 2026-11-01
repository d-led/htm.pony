use "collections"

class val ColumnView
  """
  What a shard needs to answer for one column: its index, and the synapses it
  votes with.
  """
  let index: USize
  let synapses: Array[Synapse] val

  new val create(index': USize, synapses': Array[Synapse] val) =>
    index = index'
    synapses = synapses'

actor ColumnShard
  """
  A band of columns that share one actor.

  One actor per column would cost a message in and a message out for every
  column; a shard costs that once for the whole band and reports its votes in a
  single message. The quorum still counts votes, so grouping columns does not
  change what the ballot box does.

  It owns its columns: the synapses arrive as values, one set per column, and
  are copied into columns of the shard's own. Nothing tells it to learn yet -
  that is the next message - but nothing is in the way of it either, which the
  frozen views it used to hold did.
  """
  let _columns: Array[Column] ref
  let _indices: Array[USize] val
  let _threshold: F64

  new create(columns: Array[ColumnView] val, threshold: F64) =>
    let owned = Array[Column](columns.size())
    let indices: Array[USize] iso = recover iso Array[USize] end

    for column in columns.values() do
      owned.push(Column(column.synapses))
      indices.push(column.index)
    end

    _columns = owned
    _indices = consume indices
    _threshold = threshold

  be observe(active: Array[Bool] val, ballot: Ballot tag) =>
    """
    Push the overlap of every column in the band to the round's sink.
    """
    let votes: Array[Vote] iso = recover iso Array[Vote] end

    for (position, column) in _columns.pairs() do
      let overlap = Synapses.overlap(column.synapses, active, _threshold)
      try votes.push(Vote(_indices(position)?, overlap.f64())) end
    end

    ballot.cast(consume votes)
