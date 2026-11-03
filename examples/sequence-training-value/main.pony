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
    SpatialPoolerConfig([8; 8], [64]
      where global_inhibition' = false, num_active_columns_per_inh_area' = 2.0)

  fun memory(): TemporalMemoryParams val =>
    TemporalMemoryParams(
      where
        columns' = width(),
        cells_per_column' = 4,
        activation_threshold' = 1,
        max_synapses' = 8,
        max_segments_per_cell' = 4)

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

primitive Table
  """
  A row of figures with their columns lined up.
  """
  fun pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun near(value: F64): String =>
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

  fun cell(value: F64, width: USize): String =>
    pad(near(value), width)

class Trial
  """
  One seed: both watchers learned the same cycle, then scored the clean cycle
  and the same cycle with one and then two bits knocked out of every symbol.

  Six scores and a seed, so it is also the row of the table and the thing the
  trials are added up into.
  """
  var seed: U64
  var clean_learned: F64
  var clean_wired: F64
  var one_learned: F64
  var one_wired: F64
  var two_learned: F64
  var two_wired: F64

  new nothing() =>
    seed = 0
    clean_learned = 0.0
    clean_wired = 0.0
    one_learned = 0.0
    one_wired = 0.0
    two_learned = 0.0
    two_wired = 0.0

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

    seed = seed'
    clean_learned = learned.score(clean)?
    clean_wired = wired.score(clean)?
    one_learned = learned.score(once)?
    one_wired = wired.score(once)?
    two_learned = learned.score(twice)?
    two_wired = wired.score(twice)?

  fun plus(other: Trial): Trial =>
    let total = Trial.nothing()
    total.seed = seed
    total.clean_learned = clean_learned + other.clean_learned
    total.clean_wired = clean_wired + other.clean_wired
    total.one_learned = one_learned + other.one_learned
    total.one_wired = one_wired + other.one_wired
    total.two_learned = two_learned + other.two_learned
    total.two_wired = two_wired + other.two_wired
    total

  fun scaled(per: F64): Trial =>
    let averaged = Trial.nothing()
    averaged.clean_learned = clean_learned / per
    averaged.clean_wired = clean_wired / per
    averaged.one_learned = one_learned / per
    averaged.one_wired = one_wired / per
    averaged.two_learned = two_learned / per
    averaged.two_wired = two_wired / per
    averaged

  fun row(): String => row_called(seed.string())

  fun row_called(label: String): String =>
    Table.pad(label, 8)
      + Table.cell(clean_learned, 10)
      + Table.cell(clean_wired, 10)
      + Table.cell(one_learned, 10)
      + Table.cell(one_wired, 10)
      + Table.cell(two_learned, 11)
      + Table.near(two_wired)

class Scores
  """
  The trials added up, and the two comparisons the study is for: how often the
  learned pooler gave the better sequence at one and at two bits of damage.
  """
  var total: Trial = Trial.nothing()
  var better_once: USize = 0
  var better_twice: USize = 0
  var trials: USize = 0

  new create() => None

  fun ref add(trial: Trial) =>
    total = total.plus(trial)
    trials = trials + 1
    if trial.one_learned < trial.one_wired then better_once = better_once + 1 end
    if trial.two_learned < trial.two_wired then better_twice = better_twice + 1 end

  fun mean(): Trial => total.scaled(trials.f64())

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
      let runs = _trials()?
      _header()
      let scores = _rows(runs)
      _summary(scores)
      env.exitcode(0)
    else
      _env.out.print("the study failed")
      _env.exitcode(1)
    end

  fun _trials(): Array[Trial] ? =>
    let runs: Array[Trial] = Array[Trial]
    for seed in Study.seeds().values() do
      runs.push(Trial(seed)?)
    end
    runs

  fun _header() =>
    _env.out.print(Study.symbols().string() + " symbols of "
      + Study.bits().string() + " bits in " + Study.width().string()
      + ", a cycle of them: " + Study.warming().string()
      + " passes to warm the pooler, " + Study.passes().string()
      + " to learn the sequence")
    _env.out.print("")
    _env.out.print("an anomaly score is the share of a step's columns the")
    _env.out.print("memory did not expect: lower means the sequence was followed")
    _env.out.print("")
    _env.out.print(Table.pad("seed", 8) + Table.pad("clean: L", 10)
      + Table.pad("W", 10) + Table.pad("1 bit: L", 10) + Table.pad("W", 10)
      + Table.pad("2 bits: L", 11) + "W")

  fun _rows(runs: Array[Trial]): Scores =>
    """
    A row per seed, and everything the summary needs on the way.
    """
    let scores = Scores.create()
    for trial in runs.values() do
      scores.add(trial)
      _env.out.print(trial.row())
    end
    scores

  fun _summary(scores: Scores) =>
    if scores.trials == 0 then return end

    _env.out.print(scores.mean().row_called("mean"))
    _env.out.print("")
    _env.out.print("the learned pooler gave a better sequence on "
      + scores.better_once.string() + " of " + scores.trials.string()
      + " seeds at one bit of damage,")
    _env.out.print("and on " + scores.better_twice.string() + " of "
      + scores.trials.string() + " at two.")

  fun _pad(text: String, width: USize): String => Table.pad(text, width)

  fun _near(value: F64): String => Table.near(value)
