use "collections"
use "../../htm"
use "../../htm/encoders"

interface Stream
  """
  A stream to measure against: one input per step, and a warm-up during which
  every method is told what arrived but not scored.
  """
  fun inputs(): USize
  fun steps(): USize
  fun warmup(): USize
  fun input(step: USize): Array[Bool] ?

class Drift is Stream
  """
  A value that climbs from nought to one over a hundred steps and back again.

  Every step looks much like the one before it, so a method that simply repeats
  the last input is not obviously wrong; where the direction turns, it is.
  """
  let _encoder: ScalarEncoder

  new create() ? =>
    _encoder = ScalarEncoder(
      ScalarEncoderParams(23, 0.0, 1.0 where radius' = 0.5))?

  fun inputs(): USize => _encoder.n

  fun steps(): USize => 400

  fun warmup(): USize => 100

  fun input(step: USize): Array[Bool] ? =>
    match _encoder.encode(_value(step), false)
    | let bits: Array[Bool] => bits
    else
      error
    end

  fun _value(step: USize): F64 =>
    let phase = (step % 200).f64()
    if phase <= 100.0 then
      phase / 100.0
    else
      (200.0 - phase) / 100.0
    end

class Alphabet is Stream
  """
  Six symbols repeated in a fixed order, none of them sharing a bit with
  another: the last input says nothing about what comes next, so only a method
  that has learned the order can be right about it.
  """
  let _encoder: CategoryEncoder
  let _order: Array[String] val

  new create() ? =>
    _order = ["kick"; "snare"; "hat"; "tom"; "clap"; "rim"]
    _encoder = CategoryEncoder(_order, 6)?

  fun inputs(): USize => _encoder.width()

  fun steps(): USize => _order.size() * 60

  fun warmup(): USize => _order.size() * 10

  fun input(step: USize): Array[Bool] ? =>
    match _encoder.encode(_order(step % _order.size())?)
    | let bits: Array[Bool] => bits
    else
      error
    end

primitive Rate
  """
  A share as a percentage with one decimal, so a table of them lines up.
  """
  fun of(value: F64): String =>
    let tenths = (value * 1000.0).round().i64()
    let whole = tenths / 10
    (whole.string() + "." + (tenths - (whole * 10)).string()) + "%"

primitive Share
  """
  The answer every method gives: how much of what arrived it did not expect.
  """
  fun of(missed: USize, active: ReadSeq[USize]): F64 =>
    if active.size() == 0 then 0.0
    else missed.f64() / active.size().f64() end

primitive Columns
  """
  A step's columns as a set, so that a method can ask whether one arrived.
  """
  fun set_of(active: ReadSeq[USize]): Set[USize] =>
    let result = Set[USize]
    for column in active.values() do result.set(column) end
    result

interface Method
  """
  Asked, before the step is explained to it, which of the columns that arrived
  it failed to expect. Each one keeps what it needs from the steps before.

  Partial because one of the methods it admits is: a temporal memory refuses a
  column outside the population it was built for, and that should stop the
  measurement rather than be counted as a miss.
  """
  fun ref missed(active: ReadSeq[USize]): F64 ?

class LastInput is Method
  """
  Expects this step to look like the one before it.
  """
  var _previous: Set[USize] = Set[USize]

  fun ref missed(active: ReadSeq[USize]): F64 =>
    let unexpected = _unexpected(active)
    _previous = Columns.set_of(active)
    Share.of(unexpected, active)

  fun _unexpected(active: ReadSeq[USize]): USize =>
    var unexpected: USize = 0
    for column in active.values() do
      if not _previous.contains(column) then unexpected = unexpected + 1 end
    end
    unexpected

class FrequentColumns is Method
  """
  Expects the columns that have been active most often so far - as many of them
  as half an average step turns on, which is the reference's trivial predictor.
  """
  let _columns: USize
  let _counts: Array[USize]
  var _steps: USize = 0
  var _density: F64 = 0.0

  new create(columns: USize) =>
    _columns = columns
    _counts = Array[USize].init(0, columns)

  fun ref missed(active: ReadSeq[USize]): F64 =>
    let unexpected = _unexpected(active, _wanted())
    _count(active)
    Share.of(unexpected, active)

  fun _unexpected(active: ReadSeq[USize], wanted: USize): USize =>
    let arrived = Columns.set_of(active)
    var unexpected: USize = 0
    for (column, count) in _counts.pairs() do
      if arrived.contains(column) and not _favoured(count, wanted) then
        unexpected = unexpected + 1
      end
    end
    unexpected

  fun ref _count(active: ReadSeq[USize]) =>
    for column in active.values() do
      try _counts(column)? = _counts(column)? + 1 end
    end
    _steps = _steps + 1
    _density = _density + (active.size().f64() / _columns.f64())

  fun _wanted(): USize =>
    let average = if _steps == 0 then 0.05 else _density / _steps.f64() end
    (0.5 + (average * _columns.f64())).usize()

  fun _favoured(count: USize, wanted: USize): Bool =>
    """
    Among the most common if fewer than `wanted` columns have been active more
    often. Columns tied at the edge of that all count, so this expects a few
    more than asked for rather than an arbitrary few of the tied ones.
    """
    var more_often: USize = 0
    for other in _counts.values() do
      if other > count then more_often = more_often + 1 end
    end
    more_often < wanted

class Everything is Method
  """
  Expects every column. It is here as the end of the scale rather than as a
  competitor: a method that cannot be surprised scores nought by construction.
  """
  fun ref missed(active: ReadSeq[USize]): F64 => 0.0

class Memory is Method
  """
  The temporal memory: cells, segments, and whatever its own predictions say.
  """
  let _params: TemporalMemoryParams val
  let _memory: TemporalMemory

  new create(params: TemporalMemoryParams val) =>
    _params = params
    _memory = TemporalMemory(params)

  fun ref missed(active: ReadSeq[USize]): F64 ? =>
    _memory.compute(active, true)?.anomaly(_params)

class Study
  """
  Every method asked the same question on the same stream, in one pass, with
  the first steps left unscored so that each has something to go on.
  """
  let _names: Array[String] = Array[String]
  let _methods: Array[Method] = Array[Method]
  let _missed: Array[F64] = Array[F64]
  let _right: Array[USize] = Array[USize]
  let _warmup: USize
  var _scored: USize = 0

  new create(
    columns: USize,
    params: TemporalMemoryParams val,
    warmup: USize)
  =>
    _warmup = warmup
    _add("last input", LastInput)
    _add("most common", FrequentColumns(columns))
    _add("everything", Everything)
    _add("temporal memory", Memory(params))

  fun ref _add(label: String, method: Method) =>
    _names.push(label)
    _methods.push(method)
    _missed.push(0.0)
    _right.push(0)

  fun ref measure(step: USize, active: ReadSeq[USize]) ? =>
    if step < _warmup then
      // told the step, so that each method starts even with the others
      _tell(active)?
    else
      _score(active)?
    end

  fun ref _tell(active: ReadSeq[USize]) ? =>
    for method in _methods.values() do
      method.missed(active)?
    end

  fun ref _score(active: ReadSeq[USize]) ? =>
    _scored = _scored + 1
    var index: USize = 0
    while index < _methods.size() do
      _keep(index, _ask(index, active)?)?
      index = index + 1
    end

  fun ref _ask(index: USize, active: ReadSeq[USize]): F64 ? =>
    _methods(index)?.missed(active)?

  fun ref _keep(index: USize, answer: F64) ? =>
    _missed(index)? = _missed(index)? + answer
    if answer == 0.0 then _right(index)? = _right(index)? + 1 end

  fun steps(): USize => _scored

  fun methods(): USize => _methods.size()

  fun name(index: USize): String ? => _names(index)?

  fun mean(index: USize): F64 ? =>
    if _scored == 0 then return 0.0 end
    _missed(index)? / _scored.f64()

  fun right(index: USize): F64 ? =>
    if _scored == 0 then return 0.0 end
    _right(index)?.f64() / _scored.f64()

actor Main
  """
  Does a temporal memory expect a stream better than the two obvious ways of
  guessing, and by how much?

  Two streams, each encoded, pooled into columns and then asked of four methods
  one step at a time. Every method is asked, before the step arrives, which of
  its columns it expects: the answer kept is the share it did not. So nought
  means everything that happened was expected and one means nothing was.

  The first stream is six symbols in a fixed order, which only a memory of what
  came before can follow. The second is a value that climbs and falls, where
  repeating the last input is a real competitor and the question is what
  learning adds to it.

  Expect the memory to lead on the symbols, and the last input to win on the
  smooth value.
  """
  new create(env: Env) =>
    try
      _measure(env, "six symbols in a fixed order", Alphabet.create()?)?
      env.out.print("")
      _measure(env, "a value that climbs and falls", Drift.create()?)?
      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _measure(env: Env, what: String, stream: Stream) ? =>
    let study = Study(_params().columns, _params(), stream.warmup())
    _announce(env, what, stream)
    _run(study, _pooler(stream)?, stream)?
    _report(env, study)?

  fun _params(): TemporalMemoryParams val =>
    TemporalMemoryParams(
      where
        columns' = 256,
        cells_per_column' = 8,
        activation_threshold' = 4,
        max_segments_per_cell' = 4)

  fun _pooler(stream: Stream): SpatialPooler ? =>
    SpatialPooler(SpatialPoolerConfig([256], [stream.inputs()]
      where global_inhibition' = true), 42)?

  fun _announce(env: Env, what: String, stream: Stream) =>
    env.out.print(what)
    env.out.print(
      stream.steps().string() + " steps, the first "
        + stream.warmup().string() + " of them teaching and unscored")
    env.out.print("")

  fun _run(study: Study, pooler: SpatialPooler, stream: Stream) ? =>
    var step: USize = 0
    while step < stream.steps() do
      // the pooler settles during the warm-up and is then left alone, so that
      // what is measured from there on is the memory rather than a
      // representation that is still moving under it
      let learn = step < stream.warmup()
      study.measure(step, pooler.compute(stream.input(step)?, learn)?)?
      step = step + 1
    end

  fun _report(env: Env, study: Study) ? =>
    env.out.print("method             missed   steps right")
    var index: USize = 0
    while index < study.methods() do
      env.out.print(_row(study, index)?)
      index = index + 1
    end

  fun _row(study: Study, index: USize): String ? =>
    _pad(study.name(index)?, 19)
      + _pad(Rate.of(study.mean(index)?), 9)
      + Rate.of(study.right(index)?)

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
