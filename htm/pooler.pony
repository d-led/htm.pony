use "collections"

interface Representation
  """
  Whoever wants a representation, and so receives one when the round closes.
  """
  be represented(active: Array[USize] iso)

class val Round
  let active: Array[Bool] val
  let asker: Representation tag

  new val create(active': Array[Bool] val, asker': Representation tag) =>
    active = active'
    asker = asker'

actor Pooler is Tally
  """
  The coordinator. It pushes input down to the shards, takes their votes back
  through the BallotBox, inhibits the tally, and pushes the representation up.

  One round runs at a time: a second request waits rather than overwriting a
  tally still in flight.
  """
  let _shards: Array[ColumnShard tag] val
  let _grid: Grid val
  let _config: SpatialPoolerConfig val
  var _queue: Array[Round] = Array[Round]
  var _in_flight: Bool = false
  var _asking: (Representation tag | None) = None

  new create(shards: Array[ColumnShard tag] val, grid: Grid val, config: SpatialPoolerConfig val) =>
    _shards = shards
    _grid = grid
    _config = config

  be represent(active: Array[Bool] val, asker: Representation tag) =>
    _queue.push(Round(active, asker))
    _pump()

  be tallied(votes: Array[Vote] iso) =>
    let received: Array[Vote] val = consume votes
    _in_flight = false

    let winners = _winners(received)
    let answer: Array[USize] iso = recover iso Array[USize] end
    for winner in winners.values() do
      answer.push(winner)
    end

    match _asking
    | let asker: Representation tag =>
      _asking = None
      asker.represented(consume answer)
    end

    _pump()

  fun ref _pump() =>
    if _in_flight then return end

    match _take()
    | let round: Round =>
      _in_flight = true
      _asking = round.asker

      let ballot = BallotBox(this, _grid.size, _grid.size)
      for shard in _shards.values() do
        shard.observe(round.active, ballot)
      end
    end

  fun ref _take(): (Round | None) =>
    if _queue.size() == 0 then return None end
    try _queue.shift()? else None end

  fun _winners(votes: Array[Vote] val): Array[USize] =>
    let overlaps = Array[F64].init(0.0, _grid.size)
    for vote in votes.values() do
      try overlaps(vote.column)? = vote.overlap end
    end

    let density = _config.density(_config.inhibition_radius)
    try
      if _config.global_inhibition then
        Inhibition.winners(overlaps, (density * _grid.size.f64()).usize())?
      else
        Inhibition.local(overlaps, _grid, _config.inhibition_radius, density)?
      end
    else
      Array[USize]
    end
