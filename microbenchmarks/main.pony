use "ponybench"

actor Main is BenchmarkList
  new create(env: Env) =>
    PonyBench(env, this)

  fun tag benchmarks(bench: PonyBench) =>
    bench(DenseBinaryMatrixBenchmark(1258291, 10))

// TODO: https://github.com/htm-community/htm/blob/master/denseBinaryMatrix_test.go#L166
class iso DenseBinaryMatrixBenchmark is MicroBenchmark
  new iso create(size: USize, n: USize) =>
    true

  fun name(): String => "DenseBinaryMatrixBenchmark"

  fun apply() =>
    DoNotOptimise.observe()

