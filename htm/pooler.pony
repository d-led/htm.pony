use "collections"
use "random"

interface Representation
  """
  Whoever wants a representation, and so receives one when the round closes.

  `missing` is how many columns the round never heard from. Zero means every
  column the pooler expected answered, and the representation is the one they
  agreed on; more means it was decided without them, which is what a deadline
  buys when a shard is slow or gone. A caller that has to trust the answer can
  look at this number and decide what the answer is worth.
  """
  be represented(active: Array[USize] iso, missing: USize)

interface Shard
  """
  What the pooler needs from the columns that answer for it: a round to judge,
  and a verdict to act on.

  The pooler names this rather than `ColumnShard`, so any band of columns can be
  put behind it - including one that is slow, or one that answers nothing.

  `band` is the shard's own name: its place in the array the pooler was built
  with. A shard sends it back when it reports, which is how the pooler knows
  which band stayed silent and can ask that one again.
  """
  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag)
  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val)

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

  A round closes when every shard has answered, and without a deadline that is
  the only way it closes. With `deadline_ms` the round also closes on the votes
  that arrived in time; columns that stayed silent claim nothing, and the round
  learns from the representation those votes produce. A shard that answers after
  the deadline is dropped, so it cannot answer the round twice.

  A round that closes with bands missing is asked once more, and only of those
  bands, for one more deadline. A band that answered is never asked twice, so a
  shard that was merely slow costs one extra deadline and the round still comes
  back complete; a shard that is gone costs the same one deadline and is then
  counted in the answer's `missing`. A second round is not started in between,
  so the retry cannot be overtaken by the next request.

  One round runs at a time: a second request waits rather than overwriting a
  tally still in flight.

  The bands can be replaced while the pooler is running; the new set answers from
  the next round on. A pooler with no shards has nobody to ask, so a round is
  answered as soon as it is taken: no columns, every one of them missing.
  """
  var _shards: Array[Shard tag] val
  let _grid: Grid val
  let _config: SpatialPoolerConfig val
  let _deadline_ms: U64
  let _tie_breaker: Array[F64] val
  embed _learning: ColumnLearning

  let _queue: Array[Round] = Array[Round]
  var _current: (Round | None) = None
  var _heard: Array[Vote] val = recover val Array[Vote] end
  var _retrying: Bool = false
  var _pending: (Array[Shard tag] val | None) = None

  new create(
    shards: Array[Shard tag] val,
    grid: Grid val,
    config: SpatialPoolerConfig val,
    deadline_ms: U64 = 0,
    seed: U64 = 42)
  =>
    _shards = shards
    _grid = grid
    _config = config
    _deadline_ms = deadline_ms
    _tie_breaker = TieBreaker.of(config.num_columns(), seed)
    _learning = ColumnLearning(config, grid, config.num_inputs())

  be represent(active: Array[Bool] val, learn: Bool, asker: Representation tag) =>
    _queue.push(Round(active, learn, asker))
    _pump()

  be reconfigure(shards: Array[Shard tag] val) =>
    """
    Hand over the bands to ask from now on.

    They answer from the next round, because a round that is already out - and
    its retry - belongs to the bands it was asked of, and swapping mid-round
    would cut it in half. Nothing waits for the caller: the swap happens when
    the round in flight closes.

    What such a swap may change is who answers for the columns, not which
    columns the pooler expects. Band sets that do not cover the population are
    not refused - an actor cannot refuse a message - and show up in the answer's
    `missing` instead.
    """
    _pending = shards
    _pump()

  be tallied(votes: Array[Vote] iso, silent: Array[USize] val) =>
    let received: Array[Vote] val = consume votes

    match _current
    | let round: Round =>
      let all = _joined(_heard, received)

      if _may_retry(silent) then
        _retrying = true
        _heard = all
        _ask(round.active, silent, _unheard(all.size()))
      else
        _close(round, all)
      end
    end

    _pump()

  fun ref _close(round: Round, votes: Array[Vote] val) =>
    """
    Decide the round on the votes it holds and answer the asker.
    """
    _current = None
    _retrying = false
    _heard = recover val Array[Vote] end

    let winners = _decide(round, votes)
    let answer: Array[USize] iso = recover iso Array[USize] end
    for winner in winners.values() do
      answer.push(winner)
    end

    round.asker.represented(consume answer, _unheard(votes.size()))

  fun box _may_retry(silent: Array[USize] val): Bool =>
    """
    A round is asked again only if it closed with bands missing and a deadline
    is what closed it. Without a deadline a round waits for every vote, so there
    is nothing left to ask, and a retry that could not close would hang the
    pooler.
    """
    (not _retrying) and (_deadline_ms > 0) and (silent.size() > 0)

  fun ref _pump() =>
    if _current isnt None then return end

    match _pending
    | let shards: Array[Shard tag] val =>
      _shards = shards
      _pending = None
    end

    match _take()
    | let round: Round =>
      _current = round
      _retrying = false
      _heard = recover val Array[Vote] end
      _learning.round()

      if _shards.size() == 0 then
        // nobody to ask: a ballot with nothing expected of it would never
        // close, so the round is answered on the votes it cannot have
        _close(round, recover val Array[Vote] end)
      else
        _ask(round.active, _bands(), _grid.size)
      end
    end

  fun ref _ask(active: Array[Bool] val, bands: Array[USize] val, expected: USize) =>
    """
    Put the input to the named bands. `expected` is in votes, so a round asked
    again expects only the votes it has not heard.
    """
    let ballot = BallotBox(this, expected, expected, _deadline_ms, bands)
    for band in bands.values() do
      try _shards(band)?.observe(band, active, ballot) end
    end

  fun _bands(): Array[USize] val =>
    """
    Every band, named by its place in the array the pooler was built with.
    """
    let bands: Array[USize] iso = recover iso Array[USize] end
    var band: USize = 0
    while band < _shards.size() do
      bands.push(band)
      band = band + 1
    end
    consume bands

  fun _joined(first: Array[Vote] val, second: Array[Vote] val): Array[Vote] val =>
    """
    The votes a round holds so far, plus the ones that just came in.
    """
    let all: Array[Vote] iso = recover iso Array[Vote] end
    for vote in first.values() do
      all.push(vote)
    end
    for vote in second.values() do
      all.push(vote)
    end
    consume all

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

  fun _unheard(votes: USize): USize =>
    """
    The columns a round never heard from: the ones it expected less the ones
    that voted.
    """
    if votes < _grid.size then _grid.size - votes else 0 end

  fun box _overlaps(votes: Array[Vote] val): Array[F64] =>
    let overlaps = Array[F64].init(0.0, _grid.size)
    for vote in votes.values() do
      try overlaps(vote.column)? = vote.overlap end
    end
    overlaps

  fun box _inhibit(overlaps: Array[F64]): Array[USize] =>
    let density = _config.density(_config.inhibition_radius)
    try
      let deciding = TieBreaker.nudged(overlaps, _tie_breaker)?
      if _config.global_inhibition then
        Inhibition.winners(deciding, (density * _grid.size.f64()).usize())?
      else
        Inhibition.local(deciding, _grid, _config.inhibition_radius, density)?
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
    : Array[Shard tag] val ?
  =>
    let shards: Array[Shard tag] iso = recover iso Array[Shard tag] end
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
