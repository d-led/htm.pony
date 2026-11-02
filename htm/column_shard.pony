use "collections"

class val ColumnWiring
  """
  One column's wiring as a value: where it sits in the population, and the
  synapses it starts with.

  A `Column` is a reference object, and only the actor that owns one may move its
  permanences, so a column travels to its shard in this form instead.
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

  It owns its columns: the wiring arrives as values, one per column, and is
  copied into columns of the shard's own. It also holds the settings that decide
  what a column claims and how far it moves, so `learn` needs nothing from the
  pooler but the input and the columns the pooler chose.

  Those columns are named by their index in the population, not by their
  position in the band, because the pooler decides who learns and the pooler
  knows only the population. A column of another band is ignored.
  """
  let _columns: Array[Column] ref
  let _indices: Array[USize] val
  let _positions: Map[USize, USize] ref
  let _config: SpatialPoolerConfig val

  new create(wirings: Array[ColumnWiring] val, config: SpatialPoolerConfig val) =>
    let owned = Array[Column](wirings.size())
    let indices: Array[USize] iso = recover iso Array[USize] end
    let positions = Map[USize, USize]

    for (position, wiring) in wirings.pairs() do
      owned.push(Column(wiring.synapses))
      indices.push(wiring.index)
      positions(wiring.index) = position
    end

    _columns = owned
    _indices = consume indices
    _positions = positions
    _config = config

  be observe(active: Array[Bool] val, ballot: Ballot tag) =>
    """
    Push the overlap of every column in the band to the round's sink.

    A column matching fewer than the stimulus threshold of the input votes
    zero: it does not have enough of the input to count as a claim.
    """
    let votes: Array[Vote] iso = recover iso Array[Vote] end

    for (position, column) in _columns.pairs() do
      let claim = Synapses.overlap(column.synapses, active, _config.connection_threshold)
      let overlap: F64 =
        if claim < _config.stimulus_threshold then 0.0 else claim.f64() end
      try votes.push(Vote(_indices(position)?, overlap)) end
    end

    ballot.cast(consume votes)

  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val) =>
    """
    Move the columns the pooler named towards the input it judged them on.

    A winner is adapted to the input it won with, raised until it has enough
    connected synapses to be heard again, and trimmed. A starving column is
    raised without being adapted: keeping its receptive field and making it
    stronger is what gives a column that keeps losing another chance.
    """
    for winner in winners.values() do
      try _adapt(_columns(_positions(winner)?)?, active) end
    end

    for weak in starving.values() do
      try _raise(_columns(_positions(weak)?)?) end
    end

  fun ref _adapt(column: Column, active: Array[Bool] val) =>
    column.adapt(active, _config.permanence_increment, _config.permanence_decrement)
    column.ensure_connected(
      _config.stimulus_threshold, _config.connection_threshold, _config.raise_stride())
    column.trim(_config.trim_threshold())

  fun ref _raise(column: Column) =>
    column.strengthen_all(_config.raise_stride())
    column.trim(_config.trim_threshold())
