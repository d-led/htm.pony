use "collections"
use "random"

use @cos[F64](angle: F64)
use @sin[F64](angle: F64)
use @round[F64](value: F64)

primitive HexLattice
  """
  The nearest node of a hexagonal lattice to a given point.

  Written in axial coordinates the lattice is every point

      radius * (sqrt(3) * (q + r/2), 1.5 * r)

  for whole numbers `q` and `r`, which is how grid cells tile space: three
  families of parallel lines at sixty degrees, so a cell that fires near one
  node fires near all of them.

  Rounding a point to its nearest node is rounding the axial pair. Doing that
  directly can move the answer off the lattice, so the round happens in cube
  coordinates, where the three axes sum to zero, and the axis that moved
  furthest is then corrected to restore the sum.
  """
  fun root3(): F64 => 1.7320508075688772

  fun nearest(x: F64, y: F64, radius: F64): (F64, F64) =>
    let axial_q = (((root3() / 3.0) * x) - (y / 3.0)) / radius
    let axial_r = ((2.0 / 3.0) * y) / radius
    (let q, let r) = _rounded(axial_q, axial_r)
    (radius * ((root3() * q) + ((root3() / 2.0) * r)), radius * (1.5 * r))

  fun _rounded(axial_q: F64, axial_r: F64): (F64, F64) =>
    let axial_s = -(axial_q + axial_r)
    let q = @round(axial_q)
    let r = @round(axial_r)
    let s = @round(axial_s)
    let off_q = (q - axial_q).abs()
    let off_r = (r - axial_r).abs()
    let off_s = (s - axial_s).abs()
    if (off_q > off_r) and (off_q > off_s) then
      (-(r + s), r)
    elseif off_r > off_s then
      (q, -(q + s))
    else
      (q, r)
    end

class val GridModule
  """
  One grid spacing: the slice of the output it owns, the orientation its cells
  share, and the phase of every cell in it.

  Cells in a module fire at the same spacing and the same angle, and differ
  only in where their lattice sits, which is what makes them a module rather
  than a set of unrelated cells. The spacing is the distance between two
  neighbouring nodes, so a phase has to be able to reach that far.
  """
  let start: USize
  let stop: USize
  let period: F64
  let angle: F64
  let phases: Array[(F64, F64)] val

  new val create(
    start': USize,
    stop': USize,
    period': F64,
    angle': F64,
    phases': Array[(F64, F64)] val)
  =>
    start = start'
    stop = stop'
    period = period'
    angle = angle'
    phases = phases'

class GridCellEncoder
  """
  Encodes a 2-D location into the cells that a grid cell layer would fire.

  A location is not a value on a range, so neither the scalar encoder nor the
  category encoder applies to it: there is no range to slide a window along.
  What the cortex seems to use instead is periodicity. A cell fires near the
  nodes of a lattice with a fixed spacing, the spacing is the same for every
  cell in a module and different between modules, and each cell's lattice sits
  at its own phase. Nearby places therefore share most of their active cells,
  distant places share almost none, and several spacings together stay distinct
  over a far larger area than any one of them covers.

  The output is the indices of the cells that fire, not a dense vector: activity
  here is a small set of cells within each module, and a set is what a spatial
  pooler or a temporal memory consumes.

  This follows `GridCellEncoder` from htm.core: `size` cells split into one
  slice per period, a random phase per cell, a random orientation per module,
  the distance from the location to each cell's nearest lattice node, and the
  closest fraction `sparsity` of every module firing. It is written from that
  account of the algorithm rather than transcribed from the source, so the
  cells that fire for a given seed are not the same cells. What is meant to be
  the same is the relation the algorithm exists for: how much two places'
  activity overlaps falls with the distance between them.
  """
  let _size: USize
  let _sparsity: F64
  let _modules: Array[GridModule] val

  new create(
    size': USize,
    sparsity': F64,
    periods': Array[F64] val,
    seed: U64 = 42) ?
  =>
    """
    `size'` cells, `sparsity'` of each module's slice firing, one module per
    period, and a seed for the phases and orientations.

    The periods are the spacings the modules use. htm.core's default is
    `[6, 8.5, 12, 17, 24]` - five spacings, each about the square root of two
    times the last, so that two modules never line up again before the larger
    one repeats and the set of them covers a long stretch before any
    combination recurs. A period below four puts the nodes closer together than
    the cells that have to tell them apart.
    """
    if size' == 0 then error end
    if (sparsity' <= 0.0) or (sparsity' > 1.0) then error end
    if periods'.size() == 0 then error end

    let periods = Spacings.ascending(periods')
    let random = Rand(seed)
    _warm(random)

    _size = size'
    _sparsity = sparsity'
    _modules = _build(size', periods, random)?

  fun tag _warm(random: Rand ref) =>
    """
    Pony's generator is weak for the first few draws after seeding, which would
    make the phases follow the seed rather than chance.
    """
    var forgotten: USize = 0
    while forgotten < 16 do
      random.int(2)
      forgotten = forgotten + 1
    end

  fun tag _build(
    size: USize,
    periods: Array[F64] val,
    random: Rand ref)
    : Array[GridModule] val ?
  =>
    """
    One module per period, each owning its slice of the cells and a lattice over
    it: a phase per cell, and an orientation for the module.

    A phase is where a cell's lattice sits, and the lattices of one module have
    to stay independent of each other, so the phases are spread wider than the
    largest period by an order of magnitude.
    """
    let longest = _longest(periods)?
    let reach = 9.0 * longest
    let modules: Array[GridModule] iso = recover iso Array[GridModule] end

    var module: USize = 0
    var start: USize = 0
    for period in periods.values() do
      module = module + 1
      let stop = ((module * size) / periods.size())

      // the phases first and the orientation second: the same order the draws
      // were made in when this was one body, so the same seed still gives the
      // same layer
      let phases = _phases(start, stop, reach, random)
      let angle = 2.0 * 3.141592653589793 * random.real()

      modules.push(GridModule(start, stop, period, angle, phases))
      start = stop
    end

    consume modules

  fun tag _longest(periods: Array[F64] val): F64 ? =>
    var longest: F64 = 0.0
    for period in periods.values() do
      if period < 4.0 then error end
      if period > longest then longest = period end
    end
    longest

  fun tag _phases(start: USize, stop: USize, reach: F64, random: Rand ref)
    : Array[(F64, F64)] val
  =>
    let phases: Array[(F64, F64)] iso = recover iso Array[(F64, F64)] end

    var cell: USize = start
    while cell < stop do
      phases.push((reach * random.real(), reach * random.real()))
      cell = cell + 1
    end

    consume phases

  fun width(): USize =>
    """How many cells the encoding addresses."""
    _size

  fun encode(x: F64, y: F64): Array[USize] iso^ ? =>
    """
    The indices of the cells a grid cell layer would fire at this location,
    ascending.

    A location that is not a number activates nothing rather than an arbitrary
    part of the layer: a missing position is not a position.
    """
    let active: Array[USize] ref = Array[USize]

    if not (x.nan() or y.nan()) then
      for module in _modules.values() do
        _add_module(module, x, y, active)?
      end
    end

    _frozen(active)

  fun _frozen(cells: Array[USize] ref): Array[USize] iso^ =>
    let fixed: Array[USize] iso = recover iso Array[USize] end
    for cell in cells.values() do
      fixed.push(cell)
    end
    fixed

  fun _add_module(
    module: GridModule val,
    x: F64,
    y: F64,
    active: Array[USize] ref)
  ?
  =>
    """
    The cells of one module that fire here: the `firing` nearest of its lattice
    nodes, which is what a grid cell module does.
    """
    let gaps = _gaps(module, x, y)
    _by_nearness(gaps)?

    let firing = _firing(module)
    var taken: USize = 0

    for (_, cell) in gaps.values() do
      if taken >= firing then break end
      active.push(cell)
      taken = taken + 1
    end

  fun _gaps(module: GridModule val, x: F64, y: F64): Array[(F64, USize)] ref =>
    """
    How far each of the module's cells is from the nearest node of the lattice
    it carries, and which cell that is - the distance is what decides who fires.
    """
    let cos = @cos(module.angle)
    let sin = @sin(module.angle)
    let radius = module.period / 2.0
    let gaps: Array[(F64, USize)] ref = Array[(F64, USize)]

    var cell: USize = module.start
    for (phase_x, phase_y) in module.phases.values() do
      // the module's orientation is a rotation of the lattice, so rotating the
      // offset into the lattice's frame is the same as rotating it by the
      // opposite angle, which is the cheaper way round
      let offset_x = x - phase_x
      let offset_y = y - phase_y
      let turned_x = (cos * offset_x) - (sin * offset_y)
      let turned_y = (sin * offset_x) + (cos * offset_y)

      (let node_x, let node_y) = HexLattice.nearest(turned_x, turned_y, radius)
      let gap_x = turned_x - node_x
      let gap_y = turned_y - node_y

      gaps.push((((gap_x * gap_x) + (gap_y * gap_y)), cell))
      cell = cell + 1
    end

    gaps

  fun _firing(module: GridModule): USize =>
    """How many of a module's cells fire: its share of `sparsity`."""
    @round(_sparsity * (module.stop - module.start).f64()).usize()

  fun _by_nearness(gaps: Array[(F64, USize)] ref) ? =>
    """
    Sorts the gaps shortest first, ties to the lower cell.

    Insertion sort, because a module is tens of cells and the alternative -
    forming the whole order - buys nothing at that size. The tie rule is what
    makes the encoding a function of the location alone rather than of how the
    sort happened to break a tie.
    """
    var placed: USize = 1
    while placed < gaps.size() do
      let gap = gaps(placed)?
      var position = placed

      while (position > 0) and _nearer(gap, gaps(position - 1)?) do
        gaps.update(position, gaps(position - 1)?)?
        position = position - 1
      end

      gaps.update(position, gap)?
      placed = placed + 1
    end

  fun _nearer(left: (F64, USize), right: (F64, USize)): Bool =>
    if left._1 < right._1 then
      true
    elseif left._1 > right._1 then
      false
    else
      left._2 < right._2
    end

primitive Spacings
  """
  The periods a grid cell encoder works in.

  Ascending order is not cosmetic: each module owns the next slice of the
  output, so the order of the periods decides which cells belong to which
  spacing, and a caller who happens to list them largest first would get a
  different encoder from the same arguments.
  """
  fun ascending(periods: Array[F64] val): Array[F64] val =>
    let ordering: Array[F64] trn = recover trn Array[F64](periods.size()) end
    for period in periods.values() do
      ordering.push(period)
    end

    var placed: USize = 1
    while placed < ordering.size() do
      try
        let period = ordering(placed)?
        var position = placed
        while (position > 0) and (period < ordering(position - 1)?) do
          ordering.update(position, ordering(position - 1)?)?
          position = position - 1
        end
        ordering.update(position, period)?
      end
      placed = placed + 1
    end

    consume ordering
