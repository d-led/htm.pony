use "collections"
use "random"

interface Representation
  """
  Whoever wants a representation, and so receives one when the round closes.
  """
  be represented(active: Array[USize] iso)

class val Round
  """
  One request waiting to be run: the input to judge, whether the round teaches
  the pooler, and where the answer goes.
  """
  let active: Array[Bool] val
  let learn: Bool
  let asker: Representation tag

  new val create(active': Array[Bool] val, learn': Bool, asker': Representation tag) =>
    active = active'
    learn = learn'
    asker = asker'

actor Pooler is Tally
  """
  The coordinator. It pushes input down to the shards, takes their votes back
  through the BallotBox, inhibits the tally, and pushes the representation up.

  A learning round does more between the tally and the answer. Only inhibition
  says who won, and only the asker's input says what the winners should move
  towards, so both have to be at hand when the votes return: that is why the
  round is held here until `tallied` and not closed as soon as it is sent.

  The shards are told to learn before the asker is answered, so a round's
  `learn` leaves before the next round's `observe`. Messages between one pair of
  actors arrive in the order they were sent, so a shard cannot be shown the next
  input before it has learned from the last one, and nothing waits for a shard to
  acknowledge the `learn`.

  One round runs at a time: a second request waits rather than overwriting a
  tally still in flight.
  """
  let _shards: Array[ColumnShard tag] val
  let _grid: Grid val
  let _config: SpatialPoolerConfig val
  embed _learning: ColumnLearning

  var _queue: Array[Round] = Array[Round]
  var _current: (Round | None) = None

  new create(
    shards: Array[ColumnShard tag] val,
    grid: Grid val,
    config: SpatialPoolerConfig val)
  =>
    _shards = shards
    _grid = grid
    _config = config
    _learning = ColumnLearning(config, grid, config.num_inputs())

  be represent(active: Array[Bool] val, learn: Bool, asker: Representation tag) =>
    _queue.push(Round(active, learn, asker))
    _pump()

  be tallied(votes: Array[Vote] iso) =>
    let received: Array[Vote] val = consume votes

    match _current
    | let round: Round =>
      _current = None

      let winners = _decide(round, received)
      let answer: Array[USize] iso = recover iso Array[USize] end
      for winner in winners.values() do
        answer.push(winner)
      end

      round.asker.represented(consume answer)
    end

    _pump()

  fun ref _pump() =>
    if _current isnt None then return end

    match _take()
    | let round: Round =>
      _current = round
      _learning.round()

      let ballot = BallotBox(this, _grid.size, _grid.size)
      for shard in _shards.values() do
        shard.observe(round.active, ballot)
      end
    end

  fun ref _take(): (Round | None) =>
    if _queue.size() == 0 then return None end
    try _queue.shift()? else None end

  fun ref _decide(round: Round, votes: Array[Vote] val): Array[USize] =>
    """
    The votes turned into a representation, and - on a learning round - the
    change that representation makes to the columns.
    """
    let overlaps = _overlaps(votes)
    let winners = _inhibit(_claims(round.learn, overlaps))

    if round.learn then _learn(round, overlaps, winners) end

    winners

  fun ref _claims(learn: Bool, overlaps: Array[F64]): Array[F64] =>
    """
    The claims the round competes with. On a learning round a column that keeps
    losing competes with a claim it has not earned, so that it can win back the
    input it used to represent; an inference round competes on the raw overlaps.
    """
    if not learn then return overlaps end
    try _learning.boosted(overlaps)? else overlaps end

  fun ref _learn(round: Round, overlaps: Array[F64], winners: Array[USize]) =>
    """
    Remember the round, work out which columns need help, and send both verdicts
    to the shards that own those columns.
    """
    try
      _learning.record(overlaps, winners)?
      let starving = _learning.starving()?
      _learning.review()?

      let chosen = _frozen(winners)
      let weak = _frozen(starving)
      for shard in _shards.values() do
        shard.learn(round.active, chosen, weak)
      end
    end

  fun box _overlaps(votes: Array[Vote] val): Array[F64] =>
    let overlaps = Array[F64].init(0.0, _grid.size)
    for vote in votes.values() do
      try overlaps(vote.column)? = vote.overlap end
    end
    overlaps

  fun box _inhibit(overlaps: Array[F64]): Array[USize] =>
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

  fun _frozen(values: ReadSeq[USize]): Array[USize] val =>
    let copy: Array[USize] iso = recover iso Array[USize] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

primitive PoolerShards
  """
  Splitting a pooler's columns into bands of a given width.

  The columns are wired as `SpatialPooler` wires its own - in order, from one
  seeded generator, each raised until it can be heard and trimmed - so a pooler
  built from these bands starts where the in-process one starts.

  Where the split falls makes no difference to the answer, so this is only a
  convenience for the examples and the tests.
  """
  fun build(
    config: SpatialPoolerConfig val,
    seed: U64,
    width: USize)
    : Array[ColumnShard tag] val ?
  =>
    let shards: Array[ColumnShard tag] iso = recover iso Array[ColumnShard tag] end
    if width == 0 then return consume shards end

    let inputs = Grid(config.input_dimensions)?
    let random = Rand(seed)
    let columns = config.num_columns()

    var first: USize = 0
    while first < columns do
      let left = columns - first
      let count = if left < width then left else width end
      let wirings: Array[ColumnWiring] iso = recover iso Array[ColumnWiring] end

      var column = first
      while column < (first + count) do
        let wired = Wiring.fresh_column(config, inputs, random, column)?
        wirings.push(ColumnWiring(column, _frozen(wired.synapses)))
        column = column + 1
      end

      shards.push(ColumnShard(consume wirings, config))
      first = first + count
    end

    consume shards

  fun _frozen(values: ReadSeq[Synapse]): Array[Synapse] val =>
    let copy: Array[Synapse] iso = recover iso Array[Synapse] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy
