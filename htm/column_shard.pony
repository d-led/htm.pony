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

  It is inference-only, and not by preference: it is handed frozen synapses
  (`ColumnView`), so there is nothing here it could change. Handing it the
  columns themselves - the way `TemporalColumnShard` is handed its own - is what
  would make learning available on actors. `ColumnLearning` already holds the
  arithmetic for it; what is missing is the ownership.
  """
  let _columns: Array[ColumnView] val
  let _threshold: F64

  new create(columns: Array[ColumnView] val, threshold: F64) =>
    _columns = columns
    _threshold = threshold

  be observe(active: Array[Bool] val, ballot: Ballot tag) =>
    """
    Push the overlap of every column in the band to the round's sink.
    """
    let votes: Array[Vote] iso = recover iso Array[Vote] end

    for column in _columns.values() do
      let overlap = Synapses.overlap(column.synapses, active, _threshold)
      votes.push(Vote(column.index, overlap.f64()))
    end

    ballot.cast(consume votes)
