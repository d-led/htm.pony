use "collections"

interface TemporalObserver
  """
  Whoever asked a region for a step, and so receives the answer.
  """
  be observed(output: TemporalOutput val)

class val TemporalRequest
  """
  One step waiting to be run.
  """
  let columns: Array[USize] val
  let learn: Bool
  let asker: TemporalObserver tag

  new val create(columns': Array[USize] val, learn': Bool, asker': TemporalObserver tag) =>
    columns = columns'
    learn = learn'
    asker = asker'

actor TemporalRegion is TemporalSink
  """
  Temporal memory arranged as actors.

  The columns live in shards, which own them; the region owns the two things
  that must be in one place: the previous step's active cells, and the order the
  rounds happen in. Those are exactly what cannot be split, because every column
  needs the same previous step, and a second round cannot start before the
  first has produced one.

  A round is two passes over the shards: activate, then predict. The region
  answers only when both have come back, so an asker never sees half a step.

  Two things differ from the in-process memory, both because an actor cannot
  refuse a message. A column the memory was not built for is ignored rather than
  refused, and a region with no shards answers every step with nothing active.
  """
  let _params: TemporalMemoryParams val
  let _shards: Array[TemporalColumnShard tag] val
  var _previous: Array[Bool] val
  var _step: U64 = 0

  var _queue: Array[TemporalRequest] = Array[TemporalRequest]
  var _in_flight: Bool = false
  var _asker: (TemporalObserver tag | None) = None

  let _active: Set[USize] = Set[USize]
  let _predictive: Set[USize] = Set[USize]
  let _bursting: Set[USize] = Set[USize]
  var _awaiting: USize = 0

  new create(params: TemporalMemoryParams val, shards: Array[TemporalColumnShard tag] val) =>
    _params = params
    _shards = shards
    _previous = Array[Bool].init(false, params.cells())

  be compute(columns: Array[USize] val, learn: Bool, asker: TemporalObserver tag) =>
    _queue.push(TemporalRequest(columns, learn, asker))
    _pump()

  be activated(cells: Array[USize] val, bursting: Array[USize] val) =>
    for cell in cells.values() do
      _active.set(cell)
    end
    for column in bursting.values() do
      _bursting.set(column)
    end

    _awaiting = _awaiting - 1
    if _awaiting == 0 then _start_predicting() end

  be predicted(cells: Array[USize] val) =>
    for cell in cells.values() do
      _predictive.set(cell)
    end

    _awaiting = _awaiting - 1
    if _awaiting == 0 then _answer() end

  fun ref _pump() =>
    if _in_flight then return end

    match _take()
    | let request: TemporalRequest =>
      _in_flight = true
      _asker = request.asker
      _step = _step + 1

      _active.clear()
      _predictive.clear()
      _bursting.clear()

      let previous = _previous
      let previous_cells = _active_cells_of(previous)
      _awaiting = _shards.size()

      for shard in _shards.values() do
        shard.activate(previous, previous_cells, request.columns, request.learn, _step, this)
      end

      if _awaiting == 0 then _start_predicting() end
    end

  fun ref _start_predicting() =>
    let state = _state_of(_active)
    _previous = state

    _awaiting = _shards.size()
    for shard in _shards.values() do
      shard.predict(state, this)
    end

    if _awaiting == 0 then _answer() end

  fun ref _answer() =>
    let output = TemporalOutput(
      _ascending(_params.cells(), _active),
      _ascending(_params.cells(), _predictive),
      _ascending(_params.columns, _bursting))

    _in_flight = false

    match _asker
    | let asker: TemporalObserver tag =>
      _asker = None
      asker.observed(output)
    end

    _pump()

  fun ref _take(): (TemporalRequest | None) =>
    if _queue.size() == 0 then return None end
    try _queue.shift()? else None end

  fun _state_of(cells: Set[USize]): Array[Bool] val =>
    """
    The active cells as the memory state a shard reads: one flag per cell.

    Built in cell order rather than from the set, so the previous step reads the
    same whichever order the shards happened to answer in.
    """
    let state: Array[Bool] iso = recover iso Array[Bool] end
    var cell: USize = 0
    while cell < _params.cells() do
      state.push(cells.contains(cell))
      cell = cell + 1
    end
    consume state

  fun _ascending(limit: USize, cells: Set[USize]): Array[USize] val =>
    """
    The cells in the set that exist, in order.
    """
    let result: Array[USize] iso = recover iso Array[USize] end
    var cell: USize = 0
    while cell < limit do
      if cells.contains(cell) then
        result.push(cell)
      end
      cell = cell + 1
    end
    consume result

  fun _active_cells_of(state: Array[Bool] val): Array[USize] val =>
    let result: Array[USize] iso = recover iso Array[USize] end
    for (cell, active) in state.pairs() do
      if active then result.push(cell) end
    end
    consume result

primitive TemporalShards
  """
  Splitting a memory's columns into bands of a given width.

  Where the split falls makes no difference to the answer - that is the point of
  putting the state in the columns - so this is only a convenience for the
  examples and the tests.
  """
  fun build(
    params: TemporalMemoryParams val,
    width: USize): Array[TemporalColumnShard tag] val
  =>
    let shards: Array[TemporalColumnShard tag] iso =
      recover iso Array[TemporalColumnShard tag] end

    if width == 0 then return consume shards end

    var first: USize = 0
    while first < params.columns do
      let left = params.columns - first
      let count = if left < width then left else width end
      shards.push(TemporalColumnShard(first, count, params))
      first = first + count
    end

    consume shards
