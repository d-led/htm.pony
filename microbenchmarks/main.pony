use "pony_bench"
use "random"
use "../htm"

actor Main is BenchmarkList
  new create(env: Env) =>
    PonyBench(env, this)

  fun tag benchmarks(bench: PonyBench) =>
    bench(DenseRowAndSum)
    bench(SparseRowAndSum)

primitive Shape
  """
  One matrix shape, one set of cells and one input, shared by both benchmarks so
  the two numbers can be read against each other.

  Two thousand rows of two hundred and fifty-six columns, one cell in fifty set,
  and one input bit in sixteen on: large enough for the difference between
  reading every cell and reading only the set ones to show.
  """
  fun rows(): USize => 2000

  fun width(): USize => 256

  fun fill(): F64 => 0.02

  fun active(): F64 => 0.0625

  fun seed(): U64 => 7

  fun cells(): Array[(USize, USize)] val =>
    let random = Rand(seed())
    let drawn: Array[(USize, USize)] iso = recover iso Array[(USize, USize)] end

    var row: USize = 0
    while row < rows() do
      var col: USize = 0
      while col < width() do
        if random.real() < fill() then
          drawn.push((row, col))
        end
        col = col + 1
      end
      row = row + 1
    end

    consume drawn

  fun input(): Array[Bool] val =>
    let random = Rand(seed())
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, width()) end

    var col: USize = 0
    while col < width() do
      try values(col)? = random.real() < active() end
      col = col + 1
    end

    consume values

class iso DenseRowAndSum is MicroBenchmark
  """
  `row_and_sum` on a dense matrix, which walks every cell and tests it.
  """
  let _matrix: DenseBinaryMatrix
  let _input: Array[Bool] val

  new iso create() =>
    let matrix = DenseBinaryMatrix(Shape.width(), Shape.rows())
    for (row, col) in Shape.cells().values() do
      matrix.set(row, col, true)
    end

    _matrix = matrix
    _input = Shape.input()

  fun name(): String => "DenseBinaryMatrix.row_and_sum"

  fun ref apply() =>
    try DoNotOptimise[Array[USize]](_matrix.row_and_sum(_input)?) end
    DoNotOptimise.observe()

class iso SparseRowAndSum is MicroBenchmark
  """
  `row_and_sum` on a sparse matrix holding the same cells, which walks only the
  cells that are set.
  """
  let _matrix: SparseBinaryMatrix
  let _input: Array[Bool] val

  new iso create() =>
    let matrix = SparseBinaryMatrix(Shape.width(), Shape.rows())
    for (row, col) in Shape.cells().values() do
      matrix.set(row, col, true)
    end

    _matrix = matrix
    _input = Shape.input()

  fun name(): String => "SparseBinaryMatrix.row_and_sum"

  fun ref apply() =>
    try DoNotOptimise[Array[USize]](_matrix.row_and_sum(_input)?) end
    DoNotOptimise.observe()

