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

  The pooler owns the columns and does the work in process. Learning belongs
  here rather than in the actor layer: inhibition decides the winners only after
  every overlap is known, and learning is the winners' reaction to that verdict,
  so there is exactly one place that can make the decision. A shard holds a
  frozen view of its columns, which is what an inference-only round needs and
  what the actor layer ships today.

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
  let _random: Rand
  var _overlap_duty_cycles: Array[F64]
  var _active_duty_cycles: Array[F64]
  var _min_overlap_duty_cycles: Array[F64]
  var _min_active_duty_cycles: Array[F64]
  var _boost_factors: Array[F64]
  var _rounds: USize = 0

  // The reference recomputes the minimum duty cycles every fiftieth round. It is
  // not a parameter there either; a neighbourhood's idea of "normal activity"
  // has no reason to change faster than this.
  let _minimum_duty_cycle_period: USize = 50

  new create(config': SpatialPoolerConfig, seed: U64 = 42) ? =>
    // built from locals: a constructor cannot call its own methods until every
    // field is assigned
    let inputs = Grid(config'.input_dimensions)?
    let random = Rand(seed)

    let wired = Array[Column](config'.num_columns())
    var column: USize = 0
    while column < config'.num_columns() do
      let fresh = Column(Wiring.synapses(config', inputs, random, column)?)
      fresh.ensure_connected(
        config'.stimulus_threshold, config'.connection_threshold, config'.raise_stride())
      fresh.trim(config'.trim_threshold())
      wired.push(fresh)
      column = column + 1
    end

    config = config'
    columns = wired
    column_grid = Grid(config'.column_dimensions)?
    input_grid = inputs
    _random = random

    let total = config'.num_columns()
    _overlap_duty_cycles = Array[F64].init(0.0, total)
    _active_duty_cycles = Array[F64].init(0.0, total)
    _min_overlap_duty_cycles = Array[F64].init(0.0, total)
    _min_active_duty_cycles = Array[F64].init(0.0, total)
    _boost_factors = Array[F64].init(1.0, total)

  fun size(): USize => columns.size()

  fun ref compute(input: ReadSeq[Bool], learn: Bool = false): Array[USize] ? =>
    """
    The columns that represent this input, and - with `learn` - the change this
    input makes to the pooler.
    """
    _rounds = _rounds + 1

    let overlaps = _overlaps(input)?
    let claims = if learn then _boosted(overlaps)? else overlaps end
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
    _boost_factors(column)?

  fun _inhibit(overlaps: Array[F64]): Array[USize] ? =>
    let density = config.density(config.inhibition_radius)

    if config.global_inhibition then
      Inhibition.winners(overlaps, (density * columns.size().f64()).usize())?
    else
      Inhibition.local(overlaps, column_grid, config.inhibition_radius, density)?
    end

  fun _overlaps(input: ReadSeq[Bool]): Array[F64] ? =>
    let threshold = config.connection_threshold
    let overlaps = Array[F64](columns.size())
    for column in columns.values() do
      let claim = column.overlap(input, threshold)?
      overlaps.push(if claim < config.stimulus_threshold then 0.0 else claim.f64() end)
    end
    overlaps

  fun _boosted(overlaps: Array[F64]): Array[F64] ? =>
    let boosted = Array[F64](overlaps.size())
    var index: USize = 0
    while index < overlaps.size() do
      boosted.push(overlaps(index)? * _boost_factors(index)?)
      index = index + 1
    end
    boosted

  fun ref _learn_from(input: ReadSeq[Bool], overlaps: Array[F64], winners: Array[USize]) ? =>
    _adapt(input, winners)?
    _update_duty_cycles(overlaps, winners)?
    _bump_up_weak_columns()?
    _update_boost_factors()?

    if (_rounds % _minimum_duty_cycle_period) == 0 then
      _update_min_duty_cycles()?
    end

  fun ref _adapt(input: ReadSeq[Bool], winners: Array[USize]) ? =>
    for winner in winners.values() do
      let column = columns(winner)?
      column.adapt(input, config.permanence_increment, config.permanence_decrement)
      column.ensure_connected(
        config.stimulus_threshold, config.connection_threshold, config.raise_stride())
      column.trim(config.trim_threshold())
    end

  fun ref _update_duty_cycles(overlaps: Array[F64], winners: Array[USize]) ? =>
    let period =
      if config.duty_cycle_period > _rounds then _rounds else config.duty_cycle_period end
    let span = if period < 1 then 1 else period end

    let won = Set[USize]
    for winner in winners.values() do
      won.set(winner)
    end

    var index: USize = 0
    while index < columns.size() do
      let claim: F64 = if overlaps(index)? > 0.0 then 1.0 else 0.0 end
      let activity: F64 = if won.contains(index) then 1.0 else 0.0 end
      _overlap_duty_cycles(index)? = _rolled(_overlap_duty_cycles(index)?, claim, span)
      _active_duty_cycles(index)? = _rolled(_active_duty_cycles(index)?, activity, span)
      index = index + 1
    end

  fun _rolled(previous: F64, sample: F64, span: USize): F64 =>
    """
    The moving average the reference keeps: what happened now counts for one
    step, everything before it for the rest of the window.
    """
    (((span - 1).f64() * previous) + sample) / span.f64()

  fun ref _bump_up_weak_columns() ? =>
    """
    Raise the columns that are claiming less than their neighbours consider
    normal. A column that never wins can only lose its connections, so raising
    the whole receptive field is what gives it another chance.
    """
    var index: USize = 0
    while index < columns.size() do
      if _overlap_duty_cycles(index)? < _min_overlap_duty_cycles(index)? then
        let column = columns(index)?
        column.strengthen_all(config.raise_stride())
        column.trim(config.trim_threshold())
      end
      index = index + 1
    end

  fun ref _update_boost_factors() ? =>
    let strongest = config.max_boost
    var index: USize = 0
    while index < columns.size() do
      let normal = _min_active_duty_cycles(index)?
      let active = _active_duty_cycles(index)?

      _boost_factors(index)? =
        if (normal > 0.0) and (active < normal) then
          // from the strongest boost at no activity up to one at normal activity
          (((1.0 - strongest) / normal) * active) + strongest
        else
          1.0
        end

      index = index + 1
    end

  fun ref _update_min_duty_cycles() ? =>
    """
    Decide what counts as normal activity: a share of the busiest column, either
    over the whole population or, with local inhibition, over each column's
    neighbourhood.
    """
    if config.global_inhibition or (config.inhibition_radius > input_grid.size) then
      let overlap_ceiling = _busiest(_overlap_duty_cycles)
      let active_ceiling = _busiest(_active_duty_cycles)

      var index: USize = 0
      while index < columns.size() do
        _min_overlap_duty_cycles(index)? = config.min_overlap_duty_cycle * overlap_ceiling
        _min_active_duty_cycles(index)? = config.min_active_duty_cycle * active_ceiling
        index = index + 1
      end
    else
      _update_min_duty_cycles_locally()?
    end

  fun ref _update_min_duty_cycles_locally() ? =>
    var index: USize = 0
    while index < columns.size() do
      let near = column_grid.neighbours(index, config.inhibition_radius, false)?
      _min_overlap_duty_cycles(index)? =
        config.min_overlap_duty_cycle * _busiest_around(_overlap_duty_cycles, near, index)?
      _min_active_duty_cycles(index)? =
        config.min_active_duty_cycle * _busiest_around(_active_duty_cycles, near, index)?
      index = index + 1
    end

  fun _busiest(duty_cycles: Array[F64]): F64 =>
    var highest: F64 = 0.0
    for cycle in duty_cycles.values() do
      if cycle > highest then highest = cycle end
    end
    highest

  fun _busiest_around(duty_cycles: Array[F64], neighbours: Array[USize], column: USize): F64 ? =>
    var highest = duty_cycles(column)?
    for neighbour in neighbours.values() do
      let cycle = duty_cycles(neighbour)?
      if cycle > highest then highest = cycle end
    end
    highest
