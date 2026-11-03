use "collections"
use "random"
use "../../htm"

primitive Study
  """
  The question this study asks: once a pattern is damaged, how much of its
  representation does a pooler that learned it still reach?

  Eight patterns of eight bits in sixty-four, each shown thirty times to a
  pooler that learns and to one that only looks. Then each pattern is offered
  again with one, two and three of its set bits turned off, and then with one,
  two and three bits it never had turned on, and each pooler's answer is
  compared with what the same pooler said about the clean pattern.

  It runs over several seeds because one seed is not an experiment. The gain
  from learning moves by a factor of two between seeds, and on one kind of
  damage it changes sign, which a single run would have hidden.
  """
  fun rounds(): USize => 30

  fun pattern_count(): USize => 8

  fun bits(): USize => 8

  fun width(): USize => 64

  fun seeds(): Array[U64] => [3; 5; 11; 23; 41]

  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64]
      where global_inhibition' = false, num_active_columns_per_inh_area' = 2.0)

  fun patterns(seed: U64): Array[Array[Bool] val] val ? =>
    let random = Rand(seed)
    let drawn: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    var count: USize = 0
    while count < pattern_count() do
      drawn.push(_pattern(random)?)
      count = count + 1
    end

    consume drawn

  fun show(pooler: SpatialPooler, inputs: Array[Array[Bool] val] val, learn: Bool) ? =>
    """
    Every pattern the same number of times, in the same order, so the two
    poolers see one stream and differ only in what they do with it.
    """
    var round: USize = 0
    while round < rounds() do
      for input in inputs.values() do
        pooler.compute(input, learn)?
      end
      round = round + 1
    end

  fun answers(
    pooler: SpatialPooler,
    inputs: Array[Array[Bool] val] val)
    : Array[Array[USize] val] val ?
  =>
    """
    What the pooler says about each input, learning nothing from it.
    """
    let said: Array[Array[USize] val] iso =
      recover iso Array[Array[USize] val] end

    for input in inputs.values() do
      said.push(_frozen(pooler.compute(input, false)?))
    end

    consume said

  fun damaged(inputs: Array[Array[Bool] val] val, off: USize)
    : Array[Array[Bool] val] val
  =>
    """
    Each pattern with its first `off` set bits turned off. Taking them in order
    keeps the damage the same from run to run.
    """
    let variants: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    for input in inputs.values() do
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

  fun grown(inputs: Array[Array[Bool] val] val, extra: USize)
    : Array[Array[Bool] val] val
  =>
    """
    Each pattern with its first `extra` unset bits turned on: the pattern as it
    would look with noise added to it.
    """
    let variants: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    for input in inputs.values() do
      let values: Array[Bool] iso = recover iso Array[Bool](input.size()) end
      var left = extra

      for bit in input.values() do
        if (not bit) and (left > 0) then
          values.push(true)
          left = left - 1
        else
          values.push(bit)
        end
      end

      variants.push(consume values)
    end

    consume variants

  fun kept(clean: ReadSeq[USize], answer: ReadSeq[USize]): F64 =>
    """
    The share of the clean answer that the second answer still names.
    """
    if clean.size() == 0 then return 0.0 end

    let named = Set[USize]
    for column in answer.values() do
      named.set(column)
    end

    var held: USize = 0
    for column in clean.values() do
      if named.contains(column) then held = held + 1 end
    end

    held.f64() / clean.size().f64()

  fun between(left: ReadSeq[USize], right: ReadSeq[USize]): F64 =>
    """
    What two different answers have in common, counted both ways round.
    """
    (kept(left, right) + kept(right, left)) / 2.0

  fun _pattern(random: Rand): Array[Bool] val ? =>
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

  fun _frozen(values: ReadSeq[USize]): Array[USize] val =>
    let copy: Array[USize] iso = recover iso Array[USize] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

class Trial
  """
  One seed's worth of the experiment, kept together so it can be printed in full
  or folded into the summary with the others.
  """
  let seed: U64
  let inputs: Array[Array[Bool] val] val
  let learning: SpatialPooler
  let looking: SpatialPooler
  let learned: Array[Array[USize] val] val
  let untouched: Array[Array[USize] val] val

  new create(seed': U64) ? =>
    let drawn = Study.patterns(seed')?
    let trained = SpatialPooler(Study.config(), seed')?
    let wired = SpatialPooler(Study.config(), seed')?

    Study.show(trained, drawn, true)?
    Study.show(wired, drawn, false)?

    seed = seed'
    inputs = drawn
    learning = trained
    looking = wired
    learned = Study.answers(trained, drawn)?
    untouched = Study.answers(wired, drawn)?

actor Main
  """
  What a pooler gets for learning.

  Runs one stream of patterns through a pooler that learns and one that only
  looks, then damages each pattern two ways and compares each pooler's answer
  with what the same pooler said about the clean pattern.

  One seed is printed in full, so the shape of the damage is visible, and then
  every seed's gain for learning, because one seed can make a fragile effect look
  certain.
  """
  let _env: Env

  new create(env: Env) =>
    _env = env

    try
      let trials: Array[Trial] = Array[Trial]
      for seed in Study.seeds().values() do
        trials.push(Trial(seed)?)
      end

      _env.out.print(Study.pattern_count().string() + " patterns of "
        + Study.bits().string() + " bits in " + Study.width().string()
        + ", shown " + Study.rounds().string() + " times each")

      _detail(trials(0)?)?
      _summary(trials)?

      _env.exitcode(0)
    else
      _env.out.print("the study failed")
      _env.exitcode(1)
    end

  fun _detail(trial: Trial) ? =>
    """
    One seed in full: what each pooler keeps as the damage grows.
    """
    _env.out.print("")
    _env.out.print("seed " + trial.seed.string() + ", in full")
    _env.out.print(_row("bits off", "learning", "looking"))

    var off: USize = 0
    while off <= 3 do
      let variants = Study.damaged(trial.inputs, off)
      _env.out.print(_row(off.string(),
        _near(_share(trial.learning, trial.learned, variants)?),
        _near(_share(trial.looking, trial.untouched, variants)?)))
      off = off + 1
    end

    _env.out.print("")
    _env.out.print(_row("bits on", "learning", "looking"))

    var extra: USize = 0
    while extra <= 3 do
      let variants = Study.grown(trial.inputs, extra)
      _env.out.print(_row(extra.string(),
        _near(_share(trial.learning, trial.learned, variants)?),
        _near(_share(trial.looking, trial.untouched, variants)?)))
      extra = extra + 1
    end

    _env.out.print("")
    _env.out.print("two different patterns share "
      + _near(_different(trial.learned)) + " of an answer")

  fun _summary(trials: Array[Trial]) ? =>
    """
    Every seed's gain for learning, and how many seeds favoured it.
    """
    _env.out.print("")
    _env.out.print("how much more of the answer learning kept, on 1 to 3 bits")
    _env.out.print(_row("seed", "bits off", "bits on"))

    let gains = _rows(trials)?
    if trials.size() == 0 then return end

    _env.out.print(_row("mean", _signed(gains._1 / trials.size().f64()),
      _signed(gains._2 / trials.size().f64())))
    _reading(trials.size(), gains)

  fun _rows(trials: Array[Trial]): (F64, F64, USize, USize) ? =>
    """
    One row per seed, and the totals the mean and the two counts come from.
    """
    var lost: F64 = 0.0
    var gained: F64 = 0.0
    var lost_seeds: USize = 0
    var gained_seeds: USize = 0

    for trial in trials.values() do
      let off = _lost(trial)?
      let on = _gained(trial)?

      if off > 0.0 then lost_seeds = lost_seeds + 1 end
      if on > 0.0 then gained_seeds = gained_seeds + 1 end

      lost = lost + off
      gained = gained + on

      _env.out.print(_row(trial.seed.string(), _signed(off), _signed(on)))
    end

    (lost, gained, lost_seeds, gained_seeds)

  fun _reading(seeds: USize, gains: (F64, F64, USize, USize)) =>
    """
    What the two columns say about each other.
    """
    let per = seeds.f64()

    _env.out.print("")
    _env.out.print("learning kept more of the answer on " + gains._3.string()
      + " of " + seeds.string() + " seeds when a pattern lost bits,")
    _env.out.print("and on " + gains._4.string() + " of " + seeds.string()
      + " when it gained bits it never had.")

    if (gains._1 / per) > (gains._2 / per) then
      _env.out.print("Losing bits is where the learning pays most.")
    else
      _env.out.print("Adding bits pays the learned pooler about as well.")
    end

  fun _lost(trial: Trial): F64 ? =>
    _gap(trial, true)?

  fun _gained(trial: Trial): F64 ? =>
    _gap(trial, false)?

  fun _gap(trial: Trial, biting: Bool): F64 ? =>
    """
    How much more of the answer the learned pooler kept, averaged over one, two
    and three damaged bits. `biting` takes bits away, otherwise it adds them.
    """
    var total: F64 = 0.0

    var bits: USize = 1
    while bits <= 3 do
      var variants: Array[Array[Bool] val] val =
        recover val Array[Array[Bool] val] end

      if biting then
        variants = Study.damaged(trial.inputs, bits)
      else
        variants = Study.grown(trial.inputs, bits)
      end

      let by_learning = _share(trial.learning, trial.learned, variants)?
      let by_looking = _share(trial.looking, trial.untouched, variants)?

      total = total + (by_learning - by_looking)
      bits = bits + 1
    end

    total / 3.0

  fun _share(
    pooler: SpatialPooler,
    clean: Array[Array[USize] val] val,
    variants: Array[Array[Bool] val] val)
    : F64 ?
  =>
    """
    How much of the clean answer survives, averaged over the patterns.
    """
    var total: F64 = 0.0
    var seen: USize = 0

    for (index, input) in variants.pairs() do
      let answer = pooler.compute(input, false)?
      total = total + Study.kept(clean(index)?, answer)
      seen = seen + 1
    end

    if seen == 0 then return 0.0 end
    total / seen.f64()

  fun _different(clean: Array[Array[USize] val] val): F64 =>
    """
    What two different patterns share, so the table above can be read against
    it: a damaged pattern scoring near this has nothing left.
    """
    var total: F64 = 0.0
    var pairs: USize = 0

    for (left_index, left) in clean.pairs() do
      for (right_index, right) in clean.pairs() do
        if left_index != right_index then
          total = total + Study.between(left, right)
          pairs = pairs + 1
        end
      end
    end

    if pairs == 0 then return 0.0 end
    total / pairs.f64()

  fun _row(first: String, second: String, third: String): String =>
    _pad(first, 12) + _pad(second, 10) + third

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun _signed(value: F64): String =>
    if value < 0.0 then _near(value) else "+" + _near(value) end

  fun _near(value: F64): String =>
    """
    Three decimals, so the columns line up.
    """
    let size = (value.abs() * 1000.0).round().usize()
    let rest = size % 1000
    let sign: String val = if value < 0.0 then "-" else "" end
    let tail: String val =
      if rest < 10 then
        "00" + rest.string()
      elseif rest < 100 then
        "0" + rest.string()
      else
        rest.string()
      end

    sign + (size / 1000).string() + "." + tail
