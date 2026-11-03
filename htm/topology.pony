// Ported from spatialPooler.go and utils/utils.go in htm-community/htm (MIT).
use "collections"

// https://github.com/htm-community/htm/blob/master/spatialPooler.go : getNeighborsND
// https://github.com/htm-community/htm/blob/master/utils/utils.go : RevCumProdInt, Mod, CartProductInt
//
// HTM keeps columns and inputs in one flat array and throws their shape away.
// A Grid gives the shape back: it maps flat indices to coordinates, and answers
// "which cells surround this one" - the question inhibition and potential pools
// are built on.
//
// The cells of a grid are laid out row-major: for [3, 3], index 4 is the centre.

class val Grid
  let _dims: Array[USize] val
  let _bounds: Array[USize] val
  let size: USize

  new val create(dims': Array[USize] val) ? =>
    """
    A grid of the given dimensions. Fails when a dimension is missing or zero:
    a grid without cells has no meaningful topology.
    """
    let count = dims'.size()
    if count == 0 then error end

    for d in dims'.values() do
      if d == 0 then error end
    end
    _dims = dims'

    // _bounds(i) is how much one step along dimension i is worth in the flat
    // array: [3, 3] -> [3, 1].
    let bounds = recover trn Array[USize].init(1, count) end
    var i = count
    while i > 1 do
      i = i - 1
      bounds(i - 1)? = bounds(i)? * _dims(i)?
    end
    _bounds = consume bounds

    size = _dims(0)? * _bounds(0)?

  fun box coords(flat: USize): Array[USize] ? =>
    """
    The coordinates of a flat index.
    """
    if flat >= size then error end

    let result = Array[USize](_dims.size())
    var i: USize = 0
    let count = _dims.size()
    while i < count do
      result.push((flat / _bounds(i)?) % _dims(i)?)
      i = i + 1
    end
    result

  fun box flatten(coords': ReadSeq[USize]): USize ? =>
    """
    The flat index of a coordinate tuple.
    """
    let count = _dims.size()
    if coords'.size() != count then error end

    var flat: USize = 0
    var i: USize = 0
    while i < count do
      let c = coords'(i)?
      if c >= _dims(i)? then error end
      flat = flat + (c * _bounds(i)?)
      i = i + 1
    end
    flat

  fun box neighbours(flat: USize, radius: USize, wrap_around: Bool): Array[USize] ? =>
    """
    The cells within `radius` steps of the given cell in every dimension, as a
    set (each cell once), without the cell itself. With `wrap_around` the far
    edge of a dimension is adjacent to the near edge.
    """
    if flat >= size then error end

    let ranges = _ranges(coords(flat)?, radius, wrap_around)?
    _over_the_product(ranges, flat)?

  fun box _ranges(
    centre: ReadSeq[USize],
    radius: USize,
    wrap_around: Bool)
    : Array[Array[USize]] ?
  =>
    """
    One range per dimension: the cells `radius` steps either side of the centre
    along that axis, or as many as exist when there is no wrap-around.
    """
    let ranges = Array[Array[USize]](_dims.size())

    var i: USize = 0
    while i < _dims.size() do
      ranges.push(_axis_range(centre(i)?, _dims(i)?, radius, wrap_around))
      i = i + 1
    end

    ranges

  fun box _over_the_product(ranges: Array[Array[USize]], flat: USize): Array[USize] ? =>
    """
    Every cell the ranges enclose, each once and never the centre itself.

    Walked with an odometer: the last dimension advances fastest, as in the Go
    implementation.
    """
    let count = ranges.size()
    let result = Array[USize]
    let seen = Set[USize]

    let cursor = Array[USize].init(0, count)
    var more = true
    while more do
      let candidate = _flattened(ranges, cursor)?

      if (candidate != flat) and not seen.contains(candidate) then
        seen.set(candidate)
        result.push(candidate)
      end

      more = _advance(ranges, cursor)?
    end

    result

  fun box _flattened(ranges: Array[Array[USize]], cursor: Array[USize]): USize ? =>
    var candidate: USize = 0
    var d: USize = 0
    while d < ranges.size() do
      candidate = candidate + (ranges(d)?(cursor(d)?)? * _bounds(d)?)
      d = d + 1
    end
    candidate

  fun box _advance(ranges: Array[Array[USize]], cursor: Array[USize]): Bool ? =>
    """
    Step the odometer on by one, and say whether it is still inside the ranges.
    """
    var k = cursor.size()
    while k > 0 do
      k = k - 1
      let next = cursor(k)? + 1
      if next < ranges(k)?.size() then
        cursor(k)? = next
        return true
      end
      cursor(k)? = 0
    end

    false

  fun box _axis_range(centre: USize, dimension: USize, radius: USize, wrap_around: Bool): Array[USize] =>
    let range = Array[USize]
    let span = (radius * 2) + 1

    var j: USize = 0
    while j < span do
      if wrap_around then
        let offset = (centre.isize() - radius.isize()) + j.isize()
        range.push(_euclidean_mod(offset, dimension.isize()).usize())
      else
        // a cell below zero or past the far edge simply does not exist
        let candidate = (centre.isize() - radius.isize()) + j.isize()
        if candidate >= 0 then
          let cell = candidate.usize()
          if cell < dimension then
            range.push(cell)
          end
        end
      end
      j = j + 1
    end

    range

  fun box _euclidean_mod(value: ISize, modulus: ISize): ISize =>
    """
    A non-negative remainder, so that stepping left from the first cell lands
    on the last one.
    """
    let remainder = value % modulus
    if remainder < 0 then remainder + modulus else remainder end
