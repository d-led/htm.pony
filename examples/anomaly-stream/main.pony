use "../../htm"

actor Main
  """
  A stream with a pattern in it, and one input that breaks the pattern.

  Three inputs repeat eight times, then a fourth appears. The score is the share
  of columns the temporal memory did not expect: it falls as the pattern is
  learned and jumps when the pattern breaks.
  """
  new create(env: Env) =>
    try
      let detector = StreamingAnomalyDetector(
        SpatialPooler(SpatialPoolerConfig([64], [64]
          where
            global_inhibition' = true,
            num_active_columns_per_inh_area' = 16.0,
            local_area_density' = 0.1), 42)?,
        TemporalMemory(TemporalMemoryParams(
          where
            columns' = 64,
            cells_per_column' = 8,
            activation_threshold' = 1,
            max_segments_per_cell' = 4)))

      env.out.print("eight rounds of a b c, then d")
      env.out.print("")

      var round: USize = 0
      while round < 8 do
        _report(env, "a", detector.observe(_input([0; 1; 2; 3; 8; 9]))?)
        _report(env, "b", detector.observe(_input([16; 17; 18; 19; 24; 25]))?)
        _report(env, "c", detector.observe(_input([32; 33; 34; 35; 40; 41]))?)
        round = round + 1
      end

      env.out.print("")
      _report(env, "d", detector.observe(_input([48; 49; 50; 51; 56; 57]))?)

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _report(env: Env, name: String, score: F64) =>
    env.out.print(name + "  " + _bar(score) + "  " + score.string())

  fun _bar(score: F64): String =>
    var bar: String = ""
    var filled = (score * 20.0).round().usize()
    while filled > 0 do
      bar = bar + "#"
      filled = filled - 1
    end
    while bar.size() < 20 do
      bar = bar + "."
    end
    bar

  fun _input(bits: ReadSeq[USize]): Array[Bool] =>
    let values = Array[Bool].init(false, 64)
    for bit in bits.values() do
      try values(bit)? = true end
    end
    values
