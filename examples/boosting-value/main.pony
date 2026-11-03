use "collections"
use "../../htm"

primitive Study
  """
  What boosting is for: a column that keeps losing never shows what it would
  have recognised, so the pooler multiplies the claim of the columns that go
  unheard until they win.

  Two hundred columns compete for twenty places over five inputs of twenty
  bits. The learning rate is zero in both runs, so no permanence is ever moved
  by a winner and the only thing that can change who wins is a boost. One pooler
  may boost tenfold, the other may not boost at all; that one setting is the
  whole difference between them.

  The number to watch is how many columns have never won. The pooler works out
  what counts as normal activity every fifty inputs it sees, so the first
  checkpoint is at fifty - too early for any of that to have been applied - and
  the later ones leave boosting room to work.
  """

  fun columns(): USize => 200

  fun inputs(): USize => 200

  fun density(): F64 => 0.1

  fun checkpoints(): Array[USize] => [50; 100; 200]

  fun seeds(): Array[U64] => [3; 5; 11; 23; 41]

  fun config(max_boost: F64): SpatialPoolerConfig val =>
    """
    The reference's boost test in our terms: one competition over the whole
    population, a column may look at any input bit, and nothing is learned.
    """
    let untouched: F64 = 0.0

    SpatialPoolerConfig(
      [columns()],
      [inputs()]
    where
      global_inhibition' = true,
      num_active_columns_per_inh_area' = density() * columns().f64(),
      local_area_density' = density(),
      potential_radius' = inputs(),
      potential_pct' = 0.9,
      connection_threshold' = 0.1,
      permanence_increment' = untouched,
      inhibition_radius' = 1,
      permanence_decrement' = untouched,
      stimulus_threshold' = 0,
      duty_cycle_period' = 50,
      max_boost' = max_boost,
      min_overlap_duty_cycle' = 0.001,
      min_active_duty_cycle' = 0.1)

  fun patterns(): Array[Array[Bool] val] val ? =>
    """
    Five inputs of twenty bits, no two of which share any.
    """
    let drawn: Array[Array[Bool] val] iso =
      recover iso Array[Array[Bool] val] end

    drawn.push(_bits(0, 20)?)
    drawn.push(_bits(40, 20)?)
    drawn.push(_bits(70, 20)?)
    drawn.push(_bits(110, 20)?)
    drawn.push(_bits(150, 20)?)

    consume drawn

  fun _bits(start: USize, count: USize): Array[Bool] val ? =>
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, inputs()) end

    var offset: USize = 0
    while offset < count do
      values(start + offset)? = true
      offset = offset + 1
    end

    consume values

class Watcher
  """
  One pooler driven over the same five inputs, counting what it has heard.

  `unheard` is the count that matters: the columns that have never been part of
  a representation.
  """
  let _pooler: SpatialPooler
  let _inputs: Array[Array[Bool] val] val
  let _won: Set[USize] = Set[USize]
  var _seen: USize = 0

  new create(seed: U64, max_boost: F64) ? =>
    _pooler = SpatialPooler(Study.config(max_boost), seed)?
    _inputs = Study.patterns()?

  fun ref play(reaching: USize) ? =>
    """
    The five inputs in turn, as many times as it takes to reach the checkpoint.
    Both watchers are driven by the same count, so they see the same stream.
    """
    while _seen < reaching do
      let input = _inputs(_seen % _inputs.size())?
      for winner in _pooler.compute(input, true)?.values() do
        _won.set(winner)
      end
      _seen = _seen + 1
    end

  fun box unheard(): USize => Study.columns() - _won.size()

class Trial
  """
  One seed: the same inputs through a pooler that may boost and one that may
  not, with the count of silent columns taken from each at every checkpoint.
  """
  let seed: U64
  let unheard_boosted: Array[USize] = Array[USize]
  let unheard_flat: Array[USize] = Array[USize]

  new create(seed': U64) ? =>
    let boosted = Watcher(seed', 10.0)?
    let flat = Watcher(seed', 1.0)?

    for checkpoint in Study.checkpoints().values() do
      boosted.play(checkpoint)?
      flat.play(checkpoint)?
      unheard_boosted.push(boosted.unheard())
      unheard_flat.push(flat.unheard())
    end

    seed = seed'

  fun row(): String =>
    """
    One seed's line: the silent-column count from each pooler at every
    checkpoint, boosting first.
    """
    Table.pad(seed.string(), 8) + Table.counts(unheard_boosted) + " "
      + Table.counts(unheard_flat)

primitive Table
  """
  A row of counts with its columns lined up.
  """
  fun pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun counts(values: ReadSeq[USize]): String =>
    var line: String = ""
    for value in values.values() do
      line = line + pad(value.string(), 9)
    end
    line

actor Main
  """
  What a pooler's boosting is worth.

  Runs the same five inputs through two poolers, one that may boost the columns
  it does not hear and one that may not, and prints how many columns each has
  never heard at three checkpoints.

  Every seed is printed, because a single seed can make a fragile difference
  look certain.

  Expect the count to fall towards nought with boosting and never to move
  without it, on every seed printed.
  """
  let _env: Env

  new create(env: Env) =>
    _env = env

    try
      let runs = _trials()?
      _header()
      for trial in runs.values() do
        _env.out.print(trial.row())
      end
      _summary(runs)?
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
    _env.out.print(Study.columns().string() + " columns, "
      + (Study.density() * Study.columns().f64()).string()
      + " of them allowed to win, over five inputs of twenty bits.")
    _env.out.print("No permanence moves, so only a boost can change who wins."
      + " A checkpoint is a count")
    _env.out.print("of the inputs a pooler has seen.")
    _env.out.print("")
    _env.out.print("counted: how many columns have never won")
    _env.out.print("")
    _env.out.print(_pad("", 8) + _pad("boosting", 28) + "no boost")
    _env.out.print(_labels())

  fun _summary(runs: Array[Trial]) ? =>
    if runs.size() == 0 then return end

    let at = Study.checkpoints().size() - 1
    let heard = _at_the_end(runs, at)?

    _env.out.print("")
    _env.out.print("after " + Study.checkpoints()(at)?.string()
      + " inputs, columns never heard: "
      + _mean(heard._1, runs.size()) + " with boosting, "
      + _mean(heard._2, runs.size()) + " without")
    _env.out.print("boosting had heard every column on " + heard._3.string()
      + " of " + runs.size().string() + " seeds.")
    _env.out.print("without it the count cannot move: nothing but a boost"
      + " changes a winner here,")
    _env.out.print("so a pooler that may not boost keeps the winners it"
      + " started with.")

  fun _at_the_end(runs: Array[Trial], at: USize): (USize, USize, USize) ? =>
    """
    The two counts summed over every seed, and how many seeds had heard every
    column with boosting.
    """
    var with_boost: USize = 0
    var without: USize = 0
    var all_heard: USize = 0

    for trial in runs.values() do
      with_boost = with_boost + trial.unheard_boosted(at)?
      without = without + trial.unheard_flat(at)?
      if trial.unheard_boosted(at)? == 0 then all_heard = all_heard + 1 end
    end

    (with_boost, without, all_heard)

  fun _labels(): String =>
    """
    The checkpoint columns, once for each pooler.
    """
    var line: String = _pad("seed", 8)
    var group: USize = 0
    while group < 2 do
      for checkpoint in Study.checkpoints().values() do
        line = line + _pad("@" + checkpoint.string(), 9)
      end
      group = group + 1
      if group < 2 then line = line + " " end
    end
    line

  fun _counts(counts: Array[USize]): String => Table.counts(counts)

  fun _mean(total: USize, count: USize): String =>
    _near(total.f64() / count.f64())

  fun _pad(text: String, width: USize): String => Table.pad(text, width)

  fun _near(value: F64): String =>
    """
    One decimal, so the columns line up.
    """
    let size = (value.abs() * 10.0).round().usize()
    let rest = size % 10
    let sign: String val = if value < 0.0 then "-" else "" end
    sign + (size / 10).string() + "." + rest.string()
