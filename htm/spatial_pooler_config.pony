use "collections"

// https://github.com/htm-community/htm/blob/master/spatialPooler.go : InhibitColumns, density

class val SpatialPoolerConfig
  """
  The shape of a spatial pooler and how strictly it competes.

  Densities are fractions, not counts: the pooler asks "how much of an area may
  be active" so that the same setting keeps its meaning when the radius grows.
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
    inhibition_radius': USize = 1)
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
