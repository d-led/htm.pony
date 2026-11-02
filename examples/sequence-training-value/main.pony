use "collections"
use "random"
use "../../htm"

primitive Study
  """
  The question this study asks: does a pooler that learned the symbols make a
  sequence of them easier for the memory to follow?

  Eight symbols, one cycle of them, twelve passes to learn. Then the same cycle
  with two bits knocked out of every symbol, twice round, scoring every step. The
  score is the share of a step's columns that the memory did not expect, so a
  lower score means the pipeline followed the sequence.

  Two watchers run over the same stream and differ in one thing: whether the
  pooler learns. Their memories are built the same way and both learn, so what is
  left to compare is the representation the pooler hands over.
  """
  fun symbols(): USize => 4

  fun bits(): USize => 8

  fun width(): USize => 64

  fun warming(): USize => 20

  fun passes(): USize => 12

  fun scored(): USize => 2

  fun seeds(): Array[U64] => [3; 5; 11; 23; 41]

  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64], false, 2.0)

  fun memory(): TemporalMemoryParams val =>
    TemporalMemoryParams(width(), 4, 1, 0.5, 0.5, 0.1, 0.02, 8, 4)

  fun inputs(seed: U64): Array[Array[Bool] val] val ? =>
    """
    The symbols, drawn from one seeded generator.
    """
    let random = Rand(seed)
    let drawn: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    var count: USize = 0
    while count < symbols() do
      drawn.push(_symbol(random)?)
      count = count + 1
    end

    consume drawn

  fun damaged(cycle: Array[Array[Bool] val] val, off: USize)
    : Array[Array[Bool] val] val
  =>
    """
    Every symbol with its first `off` set bits turned off.
    """
    let variants: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    for input in cycle.values() do
      let values: Array[Bool] iso = recover iso Array[Bool](input.size()) end
      var left = off

      for bit in input.values() do
        if bit and (left > 0) then
          values.push(false)
          left = left - 1
        else
          values.push(bit)
        end
      end

      variants.push(consume values)
    end

    consume variants

  fun _symbol(random: Rand): Array[Bool] val ? =>
    """
    Eight of the sixty-four bits, each chosen at most once.
    """
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, width()) end
    let chosen = Set[USize]

    while chosen.size() < bits() do
      chosen.set(random.int(width().u64()).usize())
    end

    for bit in chosen.values() do
      values(bit)? = true
    end

    consume values

class Watcher
  """
  One pooler and one memory driven together: an input in, an anomaly score out.

  Whether the pooler learns is the only thing that differs between the two
  watchers the study compares. Both memories learn the same cycle over the same
  representation.

  The pooler is settled before the memory starts: a representation that is still
  moving while the memory learns it would make the comparison about timing
  rather than about what the pooler ended up believing.
  """
  let _pooler: SpatialPooler
  let _memory: TemporalMemory
  var _pooler_learns: Bool

  new create(seed: U64, pooler_learns: Bool) ? =>
    _pooler = SpatialPooler(Study.config(), seed)?
    _memory = TemporalMemory(Study.memory())
    _pooler_learns = pooler_learns

  fun ref warm(cycle: Array[Array[Bool] val] val) ? =>
    """
    Show the symbols to the pooler alone, then leave its permanences alone for
    the rest of the run.
    """
    if not _pooler_learns then return end

    var pass: USize = 0
    while pass < Study.warming() do
      for input in cycle.values() do
        _pooler.compute(input, true)?
      end
      pass = pass + 1
    end

    _pooler_learns = false

  fun ref watch(input: ReadSeq[Bool], teaching: Bool): F64 ? =>
    """
    One step, and how surprising it was.
    """
    let columns = _pooler.compute(input, teaching and _pooler_learns)?
    let output = _memory.compute(columns, teaching)?
    output.anomaly(_memory.params)

  fun ref learn(inputs: Array[Array[Bool] val] val) ? =>
    """
    The cycle over and over, learning as it goes.
    """
    var pass: USize = 0
    while pass < Study.passes() do
      for input in inputs.values() do
        watch(input, true)?
      end
      pass = pass + 1
    end

  fun ref score(inputs: Array[Array[Bool] val] val): F64 ? =>
    """
    The mean surprise over a few passes, learning nothing.
    """
    var total: F64 = 0.0
    var seen: USize = 0

    var pass: USize = 0
    while pass < Study.scored() do
      for input in inputs.values() do
        let step = watch(input, false)?
        total = total + step
        seen = seen + 1
      end
      pass = pass + 1
    end

    if seen == 0 then return 0.0 end
    total / seen.f64()

class Trial
  """
  One seed: both watchers learned the same cycle, then scored the clean cycle
  and the same cycle with one and then two bits knocked out of every symbol.
  """
  let seed: U64
  let clean_learned: F64
  let clean_wired: F64
  let one_learned: F64
  let one_wired: F64
  let two_learned: F64
  let two_wired: F64

  new create(seed': U64) ? =>
    let clean = Study.inputs(seed')?
    let once = Study.damaged(clean, 1)
    let twice = Study.damaged(clean, 2)

    let learned = Watcher(seed', true)?
    let wired = Watcher(seed', false)?

    learned.warm(clean)?
    wired.warm(clean)?
    learned.learn(clean)?
    wired.learn(clean)?

    let plain_learning = learned.score(clean)?
    let plain_looking = wired.score(clean)?
    let once_learning = learned.score(once)?
    let once_looking = wired.score(once)?
    let twice_learning = learned.score(twice)?
    let twice_looking = wired.score(twice)?

    seed = seed'
    clean_learned = plain_learning
    clean_wired = plain_looking
    one_learned = once_learning
    one_wired = once_looking
    two_learned = twice_learning
    two_wired = twice_looking

actor Main
  """
  What a pooler's learning is worth to the memory that sits on top of it.

  Runs one repeating cycle of symbols through two watchers - one whose pooler
  learns, one whose pooler only looks - and prints the mean anomaly score for the
  clean cycle and for the same cycle with two bits knocked out of every symbol.

  One seed is printed in full, and then every seed's pair of scores, because a
  single seed can make a fragile difference look certain.
  """
  let _env: Env

  new create(env: Env) =>
    _env = env

    try
      let runs: Array[Trial] = Array[Trial]
      for seed in Study.seeds().values() do
        runs.push(Trial(seed)?)
      end

      _env.out.print(Study.symbols().string() + " symbols of "
        + Study.bits().string() + " bits in " + Study.width().string()
        + ", a cycle of them: " + Study.warming().string()
        + " passes to warm the pooler, " + Study.passes().string()
        + " to learn the sequence")
      _env.out.print("")
      _env.out.print("an anomaly score is the share of a step's columns the")
      _env.out.print("memory did not expect: lower means the sequence was followed")
      _env.out.print("")
      _env.out.print(_pad("seed", 8) + _pad("clean: L", 10)
        + _pad("W", 10) + _pad("1 bit: L", 10) + _pad("W", 10)
        + _pad("2 bits: L", 11) + "W")

      var clean_learning: F64 = 0.0
      var clean_looking: F64 = 0.0
      var one_learning: F64 = 0.0
      var one_looking: F64 = 0.0
      var two_learning: F64 = 0.0
      var two_looking: F64 = 0.0
      var better_once: USize = 0
      var better_twice: USize = 0

      for trial in runs.values() do
        clean_learning = clean_learning + trial.clean_learned
        clean_looking = clean_looking + trial.clean_wired
        one_learning = one_learning + trial.one_learned
        one_looking = one_looking + trial.one_wired
        two_learning = two_learning + trial.two_learned
        two_looking = two_looking + trial.two_wired

        if trial.one_learned < trial.one_wired then better_once = better_once + 1 end
        if trial.two_learned < trial.two_wired then better_twice = better_twice + 1 end

        _env.out.print(_pad(trial.seed.string(), 8)
          + _pad(_near(trial.clean_learned), 10)
          + _pad(_near(trial.clean_wired), 10)
          + _pad(_near(trial.one_learned), 10)
          + _pad(_near(trial.one_wired), 10)
          + _pad(_near(trial.two_learned), 11)
          + _near(trial.two_wired))
      end

      if runs.size() == 0 then return end

      let count = runs.size().f64()
      let seeds: String val = runs.size().string()

      _env.out.print(_pad("mean", 8)
        + _pad(_near(clean_learning / count), 10)
        + _pad(_near(clean_looking / count), 10)
        + _pad(_near(one_learning / count), 10)
        + _pad(_near(one_looking / count), 10)
        + _pad(_near(two_learning / count), 11)
        + _near(two_looking / count))
      _env.out.print("")
      _env.out.print("the learned pooler gave a better sequence on "
        + better_once.string() + " of " + seeds
        + " seeds at one bit of damage,")
      _env.out.print("and on " + better_twice.string() + " of " + seeds
        + " at two.")
    else
      _env.out.print("the study failed")
      _env.exitcode(1)
    end

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun _near(value: F64): String =>
    """
    Three decimals, so the columns line up.
    """
    let size = (value.abs() * 1000.0).round().usize()
    let rest = size % 1000
    let sign = if value < 0.0 then "-" else "" end
    let tail: String val =
      if rest < 10 then
        "00" + rest.string()
      elseif rest < 100 then
        "0" + rest.string()
      else
        rest.string()
      end

    sign + (size / 1000).string() + "." + tail
