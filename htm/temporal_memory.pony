use "collections"

class TemporalMemory
  """
  Learns which columns follow which, and predicts them.

  The spatial pooler answers "what is this". This answers "what comes next": it
  takes the active columns of one step, compares them with what it remembers
  about the step before, and says which cells it expects to be active at the
  next one.

  A column holds several cells so that one column can stand for more than one
  situation. If a column was predicted, only the cells that were predicted
  become active. If it was not, every cell in the column becomes active - it
  bursts - and the memory has to pick a cell to learn with.

  Learning is on the segments, not on the columns: a segment that predicted
  correctly has its synapses moved towards the cells that were actually there.

  The state is held one `TemporalColumn` at a time, which is what makes the
  same computation available as actors: a column needs the previous step and its
  own segments, and nothing else. This class is the in-process driver over those
  columns.
  """
  let params: TemporalMemoryParams val
  let _columns: Array[TemporalColumn]
  var _previous: Array[Bool]
  var _previous_winners: Array[USize] val = recover val Array[USize] end
  var _step: U64 = 0

  new create(params': TemporalMemoryParams val) =>
    params = params'

    let columns = Array[TemporalColumn](params'.columns)
    var index: USize = 0
    while index < params'.columns do
      columns.push(TemporalColumn(index, params'))
      index = index + 1
    end

    _columns = columns
    _previous = Array[Bool].init(false, params'.cells())
  fun cells(): USize => params.cells()

  fun ref compute(active_columns: ReadSeq[USize], learn: Bool): TemporalOutput ? =>
    """
    One step. `active_columns` is what the spatial pooler answered. Fails on a
    column the memory was not built for, before anything has changed.
    """
    for column in active_columns.values() do
      if column >= params.columns then error end
    end

    _step = _step + 1

    let previous = _previous
    let previous_winners = _previous_winners
    let incoming = Set[USize]
    for column in active_columns.values() do
      incoming.set(column)
    end

    let active = Array[Bool].init(false, cells())
    let bursting: Array[USize] iso = recover iso Array[USize] end
    let winners: Array[USize] iso = recover iso Array[USize] end

    for column in _columns.values() do
      let answer = column.activate(
        previous,
        previous_winners,
        incoming.contains(column.index),
        learn,
        _step)

      for cell in answer.cells.values() do
        try active(cell)? = true end
      end
      for cell in answer.winners.values() do
        winners.push(cell)
      end
      if answer.burst then bursting.push(column.index) end
    end

    _previous = active
    _previous_winners = consume winners

    let predictive = Array[Bool].init(false, cells())
    for column in _columns.values() do
      for cell in column.predict(active).values() do
        try predictive(cell)? = true end
      end
    end

    TemporalOutput(_indexes(active), _indexes(predictive), consume bursting)

  fun _indexes(state: ReadSeq[Bool]): Array[USize] val =>
    let result: Array[USize] iso = recover iso Array[USize] end
    var index: USize = 0
    while index < state.size() do
      try
        if state(index)? then result.push(index) end
      end
      index = index + 1
    end
    consume result
