// Follows spatialPooler.go in htm-community/htm (MIT) with this repository's
// structure. See docs/sources.md.
use "random"
use "collections"

// https://github.com/htm-community/htm/blob/master/spatialPooler.go : mapPotential, initPermanence, Compute

primitive Wiring
  """
  Deciding what a column looks at before it has learned anything.

  A column is not given the whole input: it is given a receptive field - the
  inputs around its own position - and connects to a random share of those.
  The permanences start near the connection threshold so a little learning can
  push a synapse either way.
  """

  fun synapses(config: SpatialPoolerConfig, input_grid: Grid, random: Rand, column: USize): Array[Synapse] ? =>
    let receptive = receptive_field(config, input_grid, column)
    _shuffle(random, receptive)?

    let wanted = (receptive.size().f64() * config.potential_pct).round().usize()
    let count = if wanted > receptive.size() then receptive.size() else wanted end

    let result = Array[Synapse](count)
    var i: USize = 0
    while i < count do
      result.push(Synapse(receptive(i)?, _permanence(config, random)))
      i = i + 1
    end
    result

  fun fresh_column(
    config: SpatialPoolerConfig,
    input_grid: Grid,
    random: Rand,
    index: USize)
    : Column ?
  =>
    """
    A column as it starts: what `synapses` picks for it, raised until it has
    enough connected synapses to be heard, and trimmed.

    A column needs both before it can take part in a round. One wired shy of the
    minimum could never win, and a column that never wins can never learn.
    """
    let fresh = Column(synapses(config, input_grid, random, index)?)
    fresh.ensure_connected(
      config.stimulus_threshold, config.connection_threshold, config.raise_stride())
    fresh.trim(config.trim_threshold())
    fresh

  fun receptive_field(config: SpatialPoolerConfig, input_grid: Grid, column: USize): Array[USize] =>
    """
    The stretch of input a column may reach: its own position, spread evenly
    across the input, widened by the potential radius and clipped to the input.
    """
    let centre = _centre(config, input_grid, column)
    let radius = config.potential_radius.isize()
    let last = (input_grid.size - 1).isize()

    var low = centre - radius
    if low < 0 then low = 0 end

    var high = centre + radius
    if high > last then high = last end

    let field = Array[USize]
    var index = low
    while index <= high do
      field.push(index.usize())
      index = index + 1
    end
    field

  fun _centre(config: SpatialPoolerConfig, input_grid: Grid, column: USize): ISize =>
    let columns = config.num_columns().isize()
    let span = if columns > 1 then columns - 1 else 1 end
    let ratio = column.isize().f64() / span.f64()
    ((input_grid.size - 1).f64() * ratio).isize()

  fun _permanence(config: SpatialPoolerConfig, random: Rand): F64 =>
    if random.real() < 0.5 then
      // just past the threshold: a little learning can still undo the connection
      config.connection_threshold + ((random.real() * config.permanence_increment) / 4.0)
    else
      // below the threshold: connected only if learning strengthens it
      config.connection_threshold * random.real()
    end

  fun _shuffle(random: Rand, values: Array[USize]) ? =>
    if values.size() < 2 then return end

    var i = values.size() - 1
    while i > 0 do
      let j = random.int((i + 1).u64()).usize()
      let held = values(i)?
      values(i)? = values(j)?
      values(j)? = held
      i = i - 1
    end

class SpatialPooler
  """
  Turns an input into a sparse representation: the columns that recognise it.

  The pooler owns the columns and does the work in process. Inhibition can name
  a winner only once every overlap is known, and learning is the winner's
  reaction to that verdict, so a round is decided in one place.

  A round that does not learn changes nothing, so the same input always gives
  the same answer. A round that learns moves the pooler forward in four ways:
  the winners move their permanences towards the input, columns that keep
  missing out have their permanences raised, every column's activity is
  remembered, and columns that are being heard too rarely are boosted so that
  they can win again.
  """
  let config: SpatialPoolerConfig
  let columns: Array[Column]
  let column_grid: Grid
  let input_grid: Grid
  let _tie_breaker: Array[F64] val
  embed _learning: ColumnLearning

  new create(config': SpatialPoolerConfig, seed: U64 = 42) ? =>
    // built from locals: a constructor cannot call its own methods until every
    // field is assigned
    let inputs = Grid(config'.input_dimensions)?
    let random = Rand(seed)

    let wired = Array[Column](config'.num_columns())
    var column: USize = 0
    while column < config'.num_columns() do
      wired.push(Wiring.fresh_column(config', inputs, random, column)?)
      column = column + 1
    end

    config = config'
    columns = wired
    column_grid = Grid(config'.column_dimensions)?
    input_grid = inputs
    _tie_breaker = TieBreaker.of(config'.num_columns(), seed)

    _learning = ColumnLearning(config', column_grid, inputs.size)

  fun size(): USize => columns.size()

  fun ref compute(input: ReadSeq[Bool], learn: Bool = false): Array[USize] ? =>
    """
    The columns that represent this input, and - with `learn` - the change this
    input makes to the pooler.
    """
    _learning.round()

    let overlaps = _overlaps(input)?
    let claims = if learn then _learning.boosted(overlaps)? else overlaps end
    let winners = _inhibit(claims)?

    if learn then
      _learn_from(input, overlaps, winners)?
    end

    winners

  fun box boost_factor(column: USize): F64 ? =>
    """
    How much this column's claim is multiplied by while learning.

    One means the column is being heard as often as its neighbours. More means
    it keeps losing, and is being helped towards winning.
    """
    _learning.boost_factor(column)?

  fun _inhibit(claims: Array[F64]): Array[USize] ? =>
    let density = config.density(config.inhibition_radius)
    let deciding = TieBreaker.nudged(claims, _tie_breaker)?

    if config.global_inhibition then
      Inhibition.winners(deciding, (density * columns.size().f64()).usize())?
    else
      Inhibition.local(deciding, column_grid, config.inhibition_radius, density)?
    end

  fun _overlaps(input: ReadSeq[Bool]): Array[F64] ? =>
    let threshold = config.connection_threshold
    let overlaps = Array[F64](columns.size())
    for column in columns.values() do
      let claim = column.overlap(input, threshold)?
      overlaps.push(if claim < config.stimulus_threshold then 0.0 else claim.f64() end)
    end
    overlaps

  fun ref _adapt(input: ReadSeq[Bool], winners: Array[USize]) ? =>
    for winner in winners.values() do
      let column = columns(winner)?
      column.adapt(input, config.permanence_increment, config.permanence_decrement)
      column.ensure_connected(
        config.stimulus_threshold, config.connection_threshold, config.raise_stride())
      column.trim(config.trim_threshold())
    end

  fun ref _learn_from(input: ReadSeq[Bool], overlaps: Array[F64], winners: Array[USize]) ? =>
    _adapt(input, winners)?

    _learning.record(overlaps, winners)?

    for column in _learning.starving()?.values() do
      try
        let weak = columns(column)?
        weak.strengthen_all(config.raise_stride())
        weak.trim(config.trim_threshold())
      end
    end

    _learning.review()?
