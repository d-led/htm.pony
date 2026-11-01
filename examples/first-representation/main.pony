use "../../htm"
use "../../htm/encoders"

actor Main
  """
  The tutorial program: one number in, a set of columns out.

  Encodes three values with a scalar encoder, gives each encoding to a spatial
  pooler, and counts how many columns two neighbouring values share.
  """
  new create(env: Env) =>
    try
      let params = ScalarEncoderParams(23, 0, 1 where radius' = 0.5, periodic' = true)
      let encoder = ScalarEncoder(params)?

      let config = SpatialPoolerConfig([8; 8], [46], true, 2.0)
      let pooler = SpatialPooler(config, 42)?

      env.out.print("encoder output: " + encoder.n.string() + " bits")
      env.out.print("columns: " + config.num_columns().string()
        + ", active per round: " + _pad(_winners(config).string(), 4))
      env.out.print("")

      let values: Array[F64] = [0.50; 0.55; 0.60; 0.90]
      let representations = Array[Array[USize]]

      for value in values.values() do
        let encoded = _encode(encoder, value)?
        let active = pooler.compute(encoded)?
        representations.push(active)
        env.out.print(_pad(value.string(), 6) + _columns(active))
      end

      env.out.print("")
      env.out.print("columns two values share:")
      var index: USize = 0
      while (index + 1) < representations.size() do
        let here = representations(index)?
        let next = representations(index + 1)?
        env.out.print(
          _pad(values(index)?.string() + " and " + values(index + 1)?.string(), 14)
            + _shared(here, next).string())
        index = index + 1
      end

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _winners(config: SpatialPoolerConfig val): USize =>
    (config.density(config.inhibition_radius) * config.num_columns().f64()).usize()

  fun _encode(encoder: ScalarEncoder, value: F64): Array[Bool] ? =>
    match encoder.encode(value, false)
    | let bits: Array[Bool] => bits
    else
      error
    end

  fun _columns(values: ReadSeq[USize]): String =>
    var text: String = ""
    for value in values.values() do
      if text.size() > 0 then text = text + " " end
      text = text + value.string()
    end
    text

  fun _shared(left: ReadSeq[USize], right: ReadSeq[USize]): USize =>
    var count: USize = 0
    for column in left.values() do
      if _contains(right, column) then count = count + 1 end
    end
    count

  fun _contains(values: ReadSeq[USize], wanted: USize): Bool =>
    for value in values.values() do
      if value == wanted then return true end
    end
    false

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
