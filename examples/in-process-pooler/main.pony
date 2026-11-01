use "../../htm"

actor Main
  """
  The spatial pooler without actors.

  Builds a pooler, prints what each column reaches, gives it one input, and
  reads back the representation. The last section builds a second pooler with
  the same seed and compares the two answers.
  """
  new create(env: Env) =>
    try
      let config = SpatialPoolerConfig([8; 8], [64], false, 2.0)

      env.out.print("columns " + config.num_columns().string()
        + ", inputs " + config.num_inputs().string())
      env.out.print("density at radius 1: " + config.density(1).string())

      let pooler = SpatialPooler(config, 42)?
      let input = _input()

      env.out.print("")
      env.out.print("column   field      synapses")
      let sampled: Array[USize] = [0; 9; 31; 63]
      for column in sampled.values() do
        let field = Wiring.receptive_field(config, Grid([64])?, column)
        env.out.print(
          _pad(column.string(), 8)
            + _pad(field(0)?.string() + ".." + field(field.size() - 1)?.string(), 11)
            + pooler.columns(column)?.synapses.size().string())
      end

      env.out.print("")
      env.out.print("active input bits: " + _columns(_input_bits()))
      env.out.print("representation:    " + _columns(pooler.compute(input)?))

      let again = SpatialPooler(config, 42)?
      let first = pooler.compute(input)?
      let second = again.compute(input)?

      env.out.print("")
      if _same(first, second) then
        env.out.print("a second pooler with the same seed gives the same representation")
      else
        env.out.print("the same seed gave two different representations")
        env.exitcode(1)
      end
      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _input_bits(): Array[USize] =>
    [3; 5; 8; 13; 21; 44]

  fun _input(): Array[Bool] =>
    let values = Array[Bool].init(false, 64)
    for index in _input_bits().values() do
      try values(index)? = true end
    end
    values

  fun _same(left: ReadSeq[USize], right: ReadSeq[USize]): Bool =>
    if left.size() != right.size() then return false end
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? != right(index)? then return false end
        index = index + 1
      end
      true
    else
      false
    end

  fun _columns(values: ReadSeq[USize]): String =>
    var text: String = ""
    for value in values.values() do
      if text.size() > 0 then text = text + ", " end
      text = text + value.string()
    end
    text

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
