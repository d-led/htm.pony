use "../../htm/encoders"

use @round[F64](value: F64)

actor Main
  """
  A grid cell encoder turns a place into the cells a grid cell layer would fire.

  There is no range to slide a window along, so the encoding is periodicity: a
  cell fires near the nodes of a lattice, cells in a module share the spacing
  and the orientation, and modules have spacings that are not multiples of each
  other. This walks a straight line through the plane one unit at a time and
  counts how many cells each step still shares with where it started.

  A cell's receptive field, printed as a map, is the second half: the places in a
  room where one cell fires, which is the hexagonal tiling the encoding is built
  on.

  Expect about three quarters of the cells to survive a one-unit move, and fewer
  as the move grows beyond the shortest period.
  """
  let _periods: Array[F64] val = recover val [6.0; 8.5; 12.0; 17.0; 24.0] end

  new create(env: Env) =>
    try
      let encoder = GridCellEncoder(
        200, 0.25, _periods where seed = 42)?
      env.out.print(
        encoder.width().string()
          + " cells, five spacings, a quarter of each module firing")
      env.out.print("")

      env.out.print("walking east from the origin:")
      let origin = _cells(encoder, 0.0, 0.0)?
      var step: USize = 1
      while step <= 24 do
        let here = _cells(encoder, step.f64(), 0.0)?
        env.out.print(_pad(step.string() + " east", 9) + _bar(_shared(origin, here))
          + "  " + _shared(origin, here).string() + " still firing")
        step = step + 5
      end

      env.out.print("")
      env.out.print("one cell's receptive field, twelve units across and six"
        + " tall: half a unit per mark")
      _map(encoder, env)?

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _cells(encoder: GridCellEncoder, x: F64, y: F64): Array[USize] val ? =>
    recover val encoder.encode(x, y)? end

  fun _shared(left: Array[USize] val, right: Array[USize] val): F64 =>
    var common: USize = 0
    for cell in left.values() do
      if _holds(right, cell) then common = common + 1 end
    end
    common.f64() / left.size().f64()

  fun _holds(cells: Array[USize] val, wanted: USize): Bool =>
    for cell in cells.values() do
      if cell == wanted then return true end
    end
    false

  fun _bar(share: F64): String =>
    var bar: String = ""
    var marks: USize = @round(share * 20.0).usize()
    while marks > 0 do
      bar = bar + "#"
      marks = marks - 1
    end
    _pad(bar, 21)

  fun _map(encoder: GridCellEncoder, env: Env) ? =>
    let at_origin = encoder.encode(0.0, 0.0)?
    let watched = at_origin(0)?
    var y: I32 = 6
    while y >= -6 do
      var line: String = ""
      var x: I32 = -12
      while x <= 12 do
        let cells = _cells(encoder, x.f64() * 0.5, y.f64() * 0.5)?
        line = line + (if _holds(cells, watched) then "o " else ". " end)
        x = x + 1
      end
      env.out.print(line)
      y = y - 1
    end

  fun _pad(text: String, width: USize): String =>
    var padded = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
