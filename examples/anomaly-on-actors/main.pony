use "../../htm"
use @round[F64](value: F64)

actor Main is AnomalyObserver
  """
  The same stream as `anomaly-stream`, scored on actors: a pooler that turns an
  input into columns, a temporal region that learns the order they arrive in,
  and one actor that joins them into a reading.

  Three inputs repeat eight times, then a fourth appears. The score is the share
  of columns the memory did not expect; the likelihood is where that score falls
  among the scores before it. Both arrive through the callback, because a step's
  reading is a message like any other on this path.

  Expect the score and the likelihood to arrive together, and to match the
  in-process stream step for step.
  """
  let _env: Env
  var _round: USize = 0
  var _step: USize = 0

  let _config: SpatialPoolerConfig val =
    SpatialPoolerConfig([64], [64]
      where
        global_inhibition' = true,
        num_active_columns_per_inh_area' = 16.0,
        local_area_density' = 0.1)

  let _params: TemporalMemoryParams val =
    TemporalMemoryParams(
      where
        columns' = 64,
        cells_per_column' = 8,
        activation_threshold' = 1,
        max_segments_per_cell' = 4)

  new create(env: Env) =>
    _env = env

    try
      let stream = AnomalyStream(
        Pooler(PoolerShards.build(_config, 42, 16)?,
          Grid(_config.column_dimensions)?, _config, 0, 42),
        TemporalRegion(_params, TemporalShards.build(_params, 2)),
        _params,
        recover iso AnomalyLikelihood(8, 8, 200, 8, 4)? end)

      env.out.print("forty rounds of a b c, then d, scored through the actors")
      env.out.print("")
      env.out.print(_pad("step", 5) + _pad("input", 7) + "score")

      var round: USize = 0
      while round < 40 do
        _send(stream, "a", [0; 1; 2; 3; 8; 9])
        _send(stream, "b", [16; 17; 18; 19; 24; 25])
        _send(stream, "c", [32; 33; 34; 35; 40; 41])
        round = round + 1
      end
      _send(stream, "d", [48; 49; 50; 51; 56; 57])
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  be scored(score: F64, likelihood: F64) =>
    _step = _step + 1

    // the first steps are the warm-up and the last is the step that breaks the
    // pattern; in between, every tenth is enough to see the score settle
    if (_step <= 6) or ((_step % 10) == 0) or (_step == 121) then
      _env.out.print(_pad(_step.string(), 5) + _pad(_name(_step), 7)
        + _bar(score) + "  " + score.string())
    end

    if _step == 121 then
      _env.out.print("")
      _env.out.print("the score falls as the pattern is learned and jumps when"
        + " the pattern breaks")
      _env.out.print("the likelihood of each score comes with it; it needs a"
        + " long stream whose scores vary before it says anything")
      _env.exitcode(0)
    end

  fun ref _send(
    stream: AnomalyStream tag,
    name: String,
    bits: ReadSeq[USize])
  =>
    let input: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end
    for bit in bits.values() do
      try input(bit)? = true end
    end
    stream.observe(consume input, true, this)

  fun _name(step: USize): String =>
    if step == 121 then return "d" end
    let names: Array[String] val = recover val ["a"; "b"; "c"] end
    try names((step - 1) % 3)? else "?" end

  fun _bar(score: F64): String =>
    var bar: String = ""
    var filled = @round(score * 12.0).usize()
    while filled > 0 do
      bar = bar + "#"
      filled = filled - 1
    end
    while bar.size() < 12 do
      bar = bar + "."
    end
    bar

  fun _pad(text: String, width: USize): String =>
    var padded = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
