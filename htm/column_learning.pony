use "collections"

class ColumnLearning
  """
  What the pooler remembers about how its columns have been doing.

  Two moving averages per column - how often it claimed an input, and how often
  it won - and, from those, which columns are starving and how hard to push
  them. None of this touches a column's synapses: it decides, and the driver
  does. That is the seam the actors need, because the driver is the only thing
  that may reach a column's permanences.

  It is kept out of `SpatialPooler` because the pooler on actors needs the same
  arithmetic over columns it does not own.
  """
  let _config: SpatialPoolerConfig val
  let _columns: USize
  let _column_grid: Grid
  let _input_count: USize

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

  new create(config: SpatialPoolerConfig val, column_grid: Grid, input_count: USize) =>
    _config = config
    _columns = config.num_columns()
    _column_grid = column_grid
    _input_count = input_count

    _overlap_duty_cycles = Array[F64].init(0.0, _columns)
    _active_duty_cycles = Array[F64].init(0.0, _columns)
    _min_overlap_duty_cycles = Array[F64].init(0.0, _columns)
    _min_active_duty_cycles = Array[F64].init(0.0, _columns)
    _boost_factors = Array[F64].init(1.0, _columns)

  fun ref round(): USize =>
    """
    Count a round, whether or not it learned. The averages are kept over rounds,
    not over learning steps.
    """
    _rounds = _rounds + 1

  fun ref boosted(overlaps: Array[F64]): Array[F64] ? =>
    """
    The claims a round competes with: each column's overlap times how much help
    it is being given.
    """
    let helped = Array[F64](overlaps.size())
    var index: USize = 0
    while index < overlaps.size() do
      helped.push(overlaps(index)? * _boost_factors(index)?)
      index = index + 1
    end
    helped

  fun ref record(overlaps: Array[F64], winners: Array[USize]) ? =>
    """
    Remember who claimed what and who won.
    """
    let period =
      if _config.duty_cycle_period > _rounds then _rounds else _config.duty_cycle_period end
    let span = if period < 1 then 1 else period end

    let won = Set[USize]
    for winner in winners.values() do
      won.set(winner)
    end

    var index: USize = 0
    while index < _columns do
      let claim: F64 = if overlaps(index)? > 0.0 then 1.0 else 0.0 end
      let activity: F64 = if won.contains(index) then 1.0 else 0.0 end
      _overlap_duty_cycles(index)? = _rolled(_overlap_duty_cycles(index)?, claim, span)
      _active_duty_cycles(index)? = _rolled(_active_duty_cycles(index)?, activity, span)
      index = index + 1
    end

  fun box starving(): Array[USize] ? =>
    """
    The columns claiming less than their neighbours consider normal. A column
    that never wins can only lose connections, so raising its receptive field is
    what gives it another chance.
    """
    let weak = Array[USize]
    var index: USize = 0
    while index < _columns do
      if _overlap_duty_cycles(index)? < _min_overlap_duty_cycles(index)? then
        weak.push(index)
      end
      index = index + 1
    end
    weak

  fun ref review() ? =>
    """
    Work out how much help each column needs, and - every fiftieth round - what
    counts as normal activity.
    """
    if (_rounds % _minimum_duty_cycle_period) == 0 then
      _update_min_duty_cycles()?
    end

    _update_boost_factors()?

  fun box boost_factor(column: USize): F64 ? =>
    """
    How much this column's claim is multiplied by while learning.

    One means the column is being heard as often as its neighbours. More means
    it keeps losing, and is being helped towards winning.
    """
    _boost_factors(column)?

  fun ref _update_boost_factors() ? =>
    let strongest = _config.max_boost
    var index: USize = 0
    while index < _columns do
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
    if _config.global_inhibition or (_config.inhibition_radius > _input_count) then
      let overlap_ceiling = _busiest(_overlap_duty_cycles)
      let active_ceiling = _busiest(_active_duty_cycles)

      var index: USize = 0
      while index < _columns do
        _min_overlap_duty_cycles(index)? = _config.min_overlap_duty_cycle * overlap_ceiling
        _min_active_duty_cycles(index)? = _config.min_active_duty_cycle * active_ceiling
        index = index + 1
      end
    else
      _update_min_duty_cycles_locally()?
    end

  fun ref _update_min_duty_cycles_locally() ? =>
    var index: USize = 0
    while index < _columns do
      let near = _column_grid.neighbours(index, _config.inhibition_radius, false)?
      _min_overlap_duty_cycles(index)? =
        _config.min_overlap_duty_cycle * _busiest_around(_overlap_duty_cycles, near, index)?
      _min_active_duty_cycles(index)? =
        _config.min_active_duty_cycle * _busiest_around(_active_duty_cycles, near, index)?
      index = index + 1
    end

  fun _rolled(previous: F64, sample: F64, span: USize): F64 =>
    """
    The moving average the reference keeps: what happened now counts for one
    step, everything before it for the rest of the window.
    """
    (((span - 1).f64() * previous) + sample) / span.f64()

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
