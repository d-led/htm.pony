use "collections"
use "time"

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

actor TemporalRegion
  """
  Temporal memory arranged as actors.

  The columns live in shards, which own them; the region owns the two things
  that must be in one place: the previous step's active cells, and the order the
  rounds happen in. Those are exactly what cannot be split, because every column
  needs the same previous step, and a second round cannot start before the
  first has produced one.

  A round is two passes over the shards: activate, then predict. The region
  answers only when both have come back, so an asker never sees half a step.
  Each pass is one `TemporalBallot`, which is what makes a late answer belong to
  the pass it was asked for rather than to the one that happens to be open.

  Two things differ from the in-process memory, both because an actor cannot
  refuse a message. A column the memory was not built for is ignored rather than
  refused, and a region with no shards answers every step with nothing active.

  With `deadline_ms` a pass also closes on the answers that arrived in time
  instead of waiting for every shard, and the bands that stayed silent are asked
  once more, on their own and for one more deadline. A band that is still silent
  is named in the answer's `missing`. The step is still answered - the cells
  that are there are real, and a prediction without a band is a narrower
  prediction rather than a wrong one - but the answer says which band it is
  missing rather than pretending the round was complete. That distinction is
  only sound in one process, where a shard is busy rather than dead: across
  machines one retry is not enough.

  The bands can be replaced while the region runs; the new set answers from the
  next round on, so a round in flight and its retry keep the bands they were
  asked of.

  The region holds the ballot of the pass it is waiting on. That is not
  bookkeeping for its own sake: a pass that has to wait out a deadline is
  reachable only through its own timer, and a ballot nobody holds can be
  collected - with its retry timer inside it - leaving the round waiting for an
  answer that can no longer come.
  """
  let _params: TemporalMemoryParams val
  var _shards: Array[TemporalBand tag] val
  let _deadline_ms: U64
  var _pending: (Array[TemporalBand tag] val | None) = None

  var _previous: Array[Bool] val
  var _step: U64 = 0

  var _queue: Array[TemporalRequest] = Array[TemporalRequest]
  var _in_flight: Bool = false
  var _asker: (TemporalObserver tag | None) = None

  var _active: Array[USize] val = recover val Array[USize] end
  var _bursting: Array[USize] val = recover val Array[USize] end
  var _missing: Array[USize] val = recover val Array[USize] end
  var _predicting: Bool = false
  var _ballot: (TemporalBallot | None) = None

  new create(
    params: TemporalMemoryParams val,
    shards: Array[TemporalBand tag] val,
    deadline_ms: U64 = 0)
  =>
    _params = params
    _shards = shards
    _deadline_ms = deadline_ms
    _previous = Array[Bool].init(false, params.cells())

  be compute(columns: Array[USize] val, learn: Bool, asker: TemporalObserver tag) =>
    _queue.push(TemporalRequest(columns, learn, asker))
    _pump()

  be reconfigure(shards: Array[TemporalBand tag] val) =>
    """
    Hand over the bands to ask from now on.

    They answer from the next round, because a round that is already out - and
    its retry - belongs to the bands it was asked of. Nothing waits for the
    caller: the swap happens when the round in flight closes.
    """
    _pending = shards
    _pump()

  be passed(
    predicting: Bool,
    cells: Array[USize] val,
    bursting: Array[USize] val,
    missing: Array[USize] val)
  =>
    """
    One pass has closed, on every answer it was going to get.
    """
    if (not _in_flight) or (predicting != _predicting) then return end

    if predicting then
      _answer(cells, missing)
    else
      _active = cells
      _bursting = bursting
      _missing = missing
      _previous = _state_of(cells)
      _start_predicting()
    end

  fun ref _pump() =>
    if _in_flight then return end

    match _pending
    | let shards: Array[TemporalBand tag] val =>
      _shards = shards
      _pending = None
    end

    match _take()
    | let request: TemporalRequest =>
      _in_flight = true
      _asker = request.asker
      _step = _step + 1
      _start_activating(request)
    end

  fun ref _start_activating(request: TemporalRequest) =>
    """
    Ask every band which of its columns' cells this step activates.
    """
    _predicting = false

    let pass = TemporalPass.activating(
      _previous, _active_cells_of(_previous), request.columns, request.learn, _step)

    _ballot =
      TemporalBallot(this, _shards, _bands(), pass, _params.cells(), _deadline_ms)

    match _ballot
    | let ballot: TemporalBallot => ballot.run()
    end

  fun ref _start_predicting() =>
    """
    Ask every band which cells the new state makes it expect, and answer once
    both passes are in.
    """
    _predicting = true

    _ballot = TemporalBallot(
      this,
      _shards,
      _bands(),
      TemporalPass.predicting_from(_previous),
      _params.cells(),
      _deadline_ms)

    match _ballot
    | let ballot: TemporalBallot => ballot.run()
    end

  fun ref _answer(predictive: Array[USize] val, missing: Array[USize] val) =>
    let output = TemporalOutput(_active, predictive, _bursting, _together(_missing, missing))

    _in_flight = false
    _ballot = None

    match _asker
    | let asker: TemporalObserver tag =>
      _asker = None
      asker.observed(output)
    end

    _pump()

  fun ref _take(): (TemporalRequest | None) =>
    if _queue.size() == 0 then return None end
    try _queue.shift()? else None end

  fun _bands(): Array[USize] val =>
    """
    Every band, named by its place in the array the region was built with.
    """
    let bands: Array[USize] iso = recover iso Array[USize] end
    var band: USize = 0
    while band < _shards.size() do
      bands.push(band)
      band = band + 1
    end
    consume bands

  fun _together(left: Array[USize] val, right: Array[USize] val): Array[USize] val =>
    """
    The bands either pass was missing, each named once.
    """
    let both: Array[USize] iso = recover iso Array[USize] end
    for band in left.values() do both.push(band) end
    for band in right.values() do
      if not _holds(left, band) then both.push(band) end
    end
    consume both

  fun _state_of(cells: Array[USize] val): Array[Bool] val =>
    """
    The active cells as the memory state a shard reads: one flag per cell.
    """
    let state: Array[Bool] iso = recover iso Array[Bool] end
    var cell: USize = 0
    while cell < _params.cells() do
      state.push(_holds(cells, cell))
      cell = cell + 1
    end
    consume state

  fun _active_cells_of(state: Array[Bool] val): Array[USize] val =>
    let result: Array[USize] iso = recover iso Array[USize] end
    for (cell, active) in state.pairs() do
      if active then result.push(cell) end
    end
    consume result

  fun _holds(cells: ReadSeq[USize], cell: USize): Bool =>
    for one in cells.values() do
      if one == cell then return true end
    end
    false

actor TemporalBallot is TemporalSink
  """
  One pass of one round: the answers the bands give to a single question.

  It is an actor of its own so that an answer can only ever belong to the pass
  that asked for it. A shard reports into the ballot it was handed, so a slow
  band that finally answers is answering that ballot - and by then the region
  may be several rounds further on, which is exactly when counting its answer
  would be wrong.

  The pass closes when every band it asked has answered, or when the deadline
  expires. A closed pass that is short of bands asks those bands once more, on
  their own and for one more deadline, and then reports what it has: the cells
  in ascending order, and the bands that never spoke.
  """
  let _region: TemporalRegion
  let _shards: Array[TemporalBand tag] val
  let _bands: Array[USize] val
  let _pass: TemporalPass val
  let _limit: USize
  let _deadline_ms: U64
  var _timers: Timers = Timers

  let _cells: Set[USize] = Set[USize]
  let _bursting: Set[USize] = Set[USize]
  let _answered: Set[USize] = Set[USize]
  var _retried: Bool = false
  var _decided: Bool = false

  new create(
    region: TemporalRegion,
    shards: Array[TemporalBand tag] val,
    bands: Array[USize] val,
    pass: TemporalPass val,
    limit: USize,
    deadline_ms: U64)
  =>
    _region = region
    _shards = shards
    _bands = bands
    _pass = pass
    _limit = limit
    _deadline_ms = deadline_ms

  be run() =>
    """
    Put the question to every band this ballot was given.
    """
    _watch()
    _ask(_bands)

    if _bands.size() == 0 then _decide() end

  be activated(band: USize, cells: Array[USize] val, bursting: Array[USize] val) =>
    if _decided or _pass.predicting then return end

    for cell in cells.values() do _cells.set(cell) end
    for column in bursting.values() do _bursting.set(column) end
    _heard(band)

  be predicted(band: USize, cells: Array[USize] val) =>
    if _decided or (not _pass.predicting) then return end

    for cell in cells.values() do _cells.set(cell) end
    _heard(band)

  be deadline_reached() =>
    if _decided then return end

    let silent = _silent()
    if (not _retried) and (_deadline_ms > 0) and (silent.size() > 0) then
      _retried = true
      _watch()
      _ask(silent)
    else
      _decide()
    end

  fun ref _watch() =>
    """
    Start a deadline - a fresh timer wheel each time, so a retry's deadline is
    not added to a wheel that is in the middle of firing.
    """
    if _deadline_ms == 0 then return end
    _timers = Timers
    _timers(Timer(RegionDeadline(this), _deadline_ms * 1_000_000))

  fun ref _ask(bands: Array[USize] val) =>
    """
    Put the pass to the named bands. A band that has already answered is never
    asked twice, so a band that was merely busy costs one more deadline.
    """
    for band in bands.values() do
      if _answered.contains(band) then continue end
      try _shards(band)?.take(band, _pass, this) end
    end

  fun ref _heard(band: USize) =>
    if _answered.contains(band) then return end
    _answered.set(band)

    if _answered.size() >= _bands.size() then _decide() end

  fun ref _decide() =>
    _decided = true

    let cells: Array[USize] iso = recover iso Array[USize] end
    let bursting: Array[USize] iso = recover iso Array[USize] end
    var cell: USize = 0
    while cell < _limit do
      if _cells.contains(cell) then cells.push(cell) end
      cell = cell + 1
    end
    var column: USize = 0
    while column < _limit do
      if _bursting.contains(column) then bursting.push(column) end
      column = column + 1
    end

    _region.passed(_pass.predicting, consume cells, consume bursting, _silent())

  fun _silent(): Array[USize] val =>
    let silent: Array[USize] iso = recover iso Array[USize] end
    for band in _bands.values() do
      if not _answered.contains(band) then silent.push(band) end
    end
    consume silent

class val TemporalPass
  """
  One pass of one round, as the bands are asked it: either the step to
  activate, or the state to predict from.

  A value, so a ballot can put it to a band again without the band having to
  remember what it was asked.
  """
  let predicting: Bool
  let previous: Array[Bool] val
  let previous_cells: Array[USize] val
  let incoming: Array[USize] val
  let learn: Bool
  let when: U64

  new val activating(
    previous': Array[Bool] val,
    previous_cells': Array[USize] val,
    incoming': Array[USize] val,
    learn': Bool,
    when': U64)
  =>
    predicting = false
    previous = previous'
    previous_cells = previous_cells'
    incoming = incoming'
    learn = learn'
    when = when'

  new val predicting_from(previous': Array[Bool] val) =>
    predicting = true
    previous = previous'
    previous_cells = recover val Array[USize] end
    incoming = recover val Array[USize] end
    learn = false
    when = 0

class RegionDeadline is TimerNotify
  let _ballot: TemporalBallot

  new iso create(ballot: TemporalBallot) =>
    _ballot = ballot

  fun ref apply(timer: Timer, count: U64): Bool =>
    _ballot.deadline_reached()
    false

  fun ref cancel(timer: Timer) => None

primitive TemporalShards
  """
  Splitting a memory's columns into bands of a given width.

  Where the split falls makes no difference to the answer - that is the point of
  putting the state in the columns - so this is only a convenience for the
  examples and the tests.
  """
  fun build(
    params: TemporalMemoryParams val,
    width: USize): Array[TemporalBand tag] val
  =>
    let shards: Array[TemporalBand tag] iso =
      recover iso Array[TemporalBand tag] end

    if width == 0 then return consume shards end

    var first: USize = 0
    while first < params.columns do
      let left = params.columns - first
      let count = if left < width then left else width end
      shards.push(TemporalColumnShard(first, count, params))
      first = first + count
    end

    consume shards
