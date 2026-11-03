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
    _refuse(active_columns)?
    _step = _step + 1

    let reading = _read(active_columns, learn)
    let active = reading._1
    let bursting = reading._2
    let winners = reading._3

    _previous = active
    _previous_winners = _as_value(winners)

    TemporalOutput(
      _indexes(active),
      _indexes(_predicting(active)),
      _as_value(bursting))

  fun _refuse(active_columns: ReadSeq[USize]) ? =>
    """
    A column outside the population is a wiring error, and it is worth stopping
    on before any of the memory has moved.
    """
    for column in active_columns.values() do
      if column >= params.columns then error end
    end

  fun ref _read(active_columns: ReadSeq[USize], learn: Bool)
    : (Array[Bool] ref, Array[USize] ref, Array[USize] ref)
  =>
    """
    Every column's answer for this step: the cells now active, the columns that
    had to burst, and the winners the next step learns from.
    """
    let incoming = _as_set(active_columns)
    let active = Array[Bool].init(false, cells())
    let bursting: Array[USize] ref = Array[USize]
    let winners: Array[USize] ref = Array[USize]

    for column in _columns.values() do
      let answer = column.activate(
        _previous, _previous_winners, incoming.contains(column.index), learn, _step)
      _keep(active, bursting, winners, answer, column.index)
    end

    (active, bursting, winners)

  fun _keep(
    active: Array[Bool] ref,
    bursting: Array[USize] ref,
    winners: Array[USize] ref,
    answer: ColumnStep val,
    index: USize)
  =>
    for cell in answer.cells.values() do
      try active(cell)? = true end
    end
    for cell in answer.winners.values() do
      winners.push(cell)
    end
    if answer.burst then bursting.push(index) end

  fun _as_value(given: Array[USize] ref): Array[USize] val =>
    let fixed: Array[USize] iso = recover iso Array[USize] end
    for cell in given.values() do fixed.push(cell) end
    consume fixed

  fun _as_set(columns: ReadSeq[USize]): Set[USize] =>
    let result = Set[USize]
    for column in columns.values() do result.set(column) end
    result

  fun _predicting(active: ReadSeq[Bool]): Array[Bool] =>
    """
    The cells the memory expects to be active next, read from the state now.
    """
    let predictive = Array[Bool].init(false, cells())
    for column in _columns.values() do
      for cell in column.predict(active).values() do
        try predictive(cell)? = true end
      end
    end
    predictive

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
