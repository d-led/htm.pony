// Ported from spatialPooler.go in htm-community/htm (MIT) - SpParams, renamed.
use "collections"

// https://github.com/htm-community/htm/blob/master/spatialPooler.go : InhibitColumns, density

class val SpatialPoolerConfig
  """
  The shape of a spatial pooler and how strictly it competes.

  Densities are fractions, not counts: the pooler asks "how much of an area may
  be active" so that the same setting keeps its meaning when the radius grows.

  The learning settings are the ones the Go reference uses. A permanence moves by
  `permanence_increment` when its input is on and by `permanence_decrement` when
  it is off, which is deliberately lopsided: a column forgets slowly and learns
  quickly.
  """
  let column_dimensions: Array[USize] val
  let input_dimensions: Array[USize] val
  let global_inhibition: Bool
  let num_active_columns_per_inh_area: F64
  let local_area_density: F64
  let potential_radius: USize
  let potential_pct: F64
  let connection_threshold: F64
  let permanence_increment: F64
  let inhibition_radius: USize
  let permanence_decrement: F64
  let stimulus_threshold: USize
  let duty_cycle_period: USize
  let max_boost: F64
  let min_overlap_duty_cycle: F64
  let min_active_duty_cycle: F64

  new val create(
    column_dimensions': Array[USize] val,
    input_dimensions': Array[USize] val,
    global_inhibition': Bool = false,
    num_active_columns_per_inh_area': F64 = 10.0,
    local_area_density': F64 = -1.0,
    potential_radius': USize = 16,
    potential_pct': F64 = 0.5,
    connection_threshold': F64 = 0.1,
    permanence_increment': F64 = 0.1,
    inhibition_radius': USize = 1,
    permanence_decrement': F64 = 0.01,
    stimulus_threshold': USize = 0,
    duty_cycle_period': USize = 1000,
    max_boost': F64 = 10.0,
    min_overlap_duty_cycle': F64 = 0.001,
    min_active_duty_cycle': F64 = 0.001)
  =>
    column_dimensions = column_dimensions'
    input_dimensions = input_dimensions'
    global_inhibition = global_inhibition'
    num_active_columns_per_inh_area = num_active_columns_per_inh_area'
    local_area_density = local_area_density'
    potential_radius = potential_radius'
    potential_pct = potential_pct'
    connection_threshold = connection_threshold'
    permanence_increment = permanence_increment'
    inhibition_radius = inhibition_radius'
    permanence_decrement = permanence_decrement'
    stimulus_threshold = stimulus_threshold'
    duty_cycle_period = duty_cycle_period'
    max_boost = max_boost'
    min_overlap_duty_cycle = min_overlap_duty_cycle'
    min_active_duty_cycle = min_active_duty_cycle'

  fun trim_threshold(): F64 =>
    """
    The permanence below which a synapse is no longer worth keeping: half a step
    of learning, so one round of weakening can drop it.
    """
    permanence_increment / 2.0

  fun raise_stride(): F64 =>
    """
    How much a column raises its permanences when it is too weak to be heard.
    """
    connection_threshold / 10.0

  fun num_columns(): USize => Dimensions.product(column_dimensions)

  fun num_inputs(): USize => Dimensions.product(input_dimensions)

  fun density(radius: USize): F64 =>
    """
    The fraction of an inhibition area that may stay active.

    A density stated outright wins. Otherwise the request is turned into a
    fraction of one area, and capped: without the cap a small area could ask
    for more winners than it holds cells.
    """
    if local_area_density > 0 then
      return local_area_density
    end

    let area = _area(radius)
    let requested = num_active_columns_per_inh_area / area
    if requested > 0.5 then 0.5 else requested end

  fun _area(radius: USize): F64 =>
    """
    How many columns one inhibition area covers, never more than exist.
    """
    var area: F64 = 1.0
    for _ in column_dimensions.values() do
      area = area * ((2 * radius) + 1).f64()
    end

    let columns = num_columns().f64()
    if area > columns then columns else area end
