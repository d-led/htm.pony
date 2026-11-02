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
  compared with what the same pooler said about the clean pattern. Everything is
  drawn from one seed, so the numbers read the same every run.

  Both kinds of damage are measured because they pull in opposite directions,
  and a study that measured one of them would be reporting half a result.
  """
  fun rounds(): USize => 30

  fun pattern_count(): USize => 8

  fun bits(): USize => 8

  fun width(): USize => 64

  fun seed(): U64 => 11

  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64], false, 2.0)

  fun patterns(): Array[Array[Bool] val] val ? =>
    let random = Rand(seed())
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

actor Main
  """
  What a pooler gets for learning.

  Runs the same stream of patterns through a pooler that learns and one that
  only looks, then damages each pattern and prints how much of the clean
  representation each pooler still reaches. The last two lines are the two
  numbers a reader needs to judge the table: what two different patterns share,
  and how much better the learning pooler did.
  """
  let _env: Env

  new create(env: Env) =>
    _env = env

    try
      let inputs = Study.patterns()?
      let learning = SpatialPooler(Study.config(), Study.seed())?
      let looking = SpatialPooler(Study.config(), Study.seed())?

      Study.show(learning, inputs, true)?
      Study.show(looking, inputs, false)?

      let learned = Study.answers(learning, inputs)?
      let untouched = Study.answers(looking, inputs)?

      _env.out.print(Study.pattern_count().string() + " patterns of "
        + Study.bits().string() + " bits in " + Study.width().string()
        + ", shown " + Study.rounds().string() + " times each")
      _env.out.print("")
      _env.out.print(_row("bits off", "learning", "looking"))

      var off: USize = 0
      var lost: F64 = 0.0
      while off <= 3 do
        let variants = Study.damaged(inputs, off)
        let by_learning = _share(learning, learned, variants)?
        let by_looking = _share(looking, untouched, variants)?

        if off > 0 then lost = lost + (by_learning - by_looking) end

        _env.out.print(_row(off.string(), _near(by_learning), _near(by_looking)))
        off = off + 1
      end

      _env.out.print("")
      _env.out.print(_row("bits on", "learning", "looking"))

      var extra: USize = 0
      var gained: F64 = 0.0
      while extra <= 3 do
        let variants = Study.grown(inputs, extra)
        let by_learning = _share(learning, learned, variants)?
        let by_looking = _share(looking, untouched, variants)?

        if extra > 0 then gained = gained + (by_learning - by_looking) end

        _env.out.print(_row(extra.string(), _near(by_learning), _near(by_looking)))
        extra = extra + 1
      end

      _env.out.print("")
      _env.out.print("two different patterns share "
        + _near(_different(learned)) + " of an answer")
      _env.out.print("")
      _env.out.print("what learning changed, on average over 1 to 3 bits:")
      _env.out.print(_row("  bits off", _signed(lost / 3.0), ""))
      _env.out.print(_row("  bits on", _signed(gained / 3.0), ""))
      _env.out.print("")
      _env.out.print("a column that learned connected itself to the bits the")
      _env.out.print("pattern actually uses, so a pattern missing one of them still")
      _env.out.print("reaches most of the same columns. A pooler that only looked")
      _env.out.print("spread its connections over inputs the pattern never turns")
      _env.out.print("on, so the same missing bit moves its answer further.")

      _env.exitcode(0)
    else
      _env.out.print("the study failed")
      _env.exitcode(1)
    end

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
