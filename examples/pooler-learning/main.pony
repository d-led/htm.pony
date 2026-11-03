use "../../htm"

actor Main
  """
  The spatial pooler learning, and what changes when it does.

  Builds two poolers with the same seed - one that learns, one that does not -
  and shows the three things a learning round does: a winning column's
  permanences move towards the input, a column that keeps losing is boosted, and
  a column that never overlaps is raised.

  The last section checks the claim that matters: a round without learning
  changes nothing, so the same input always gives the same representation.

  Expect the winning column's permanences to rise towards the input, losing
  columns to be boosted, and the round without learning to change nothing.
  """
  new create(env: Env) =>
    try
      let code = _run(env)?
      env.exitcode(code)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _run(env: Env): I32 ? =>
    let config = SpatialPoolerConfig([8; 8], [64]
      where global_inhibition' = false, num_active_columns_per_inh_area' = 2.0)
    let pattern = _pattern()
    let learning = SpatialPooler(config, 42)?
    let watching = SpatialPooler(config, 42)?

    let winner = _represent(env, learning, pattern)?
    let before = _permanences(learning.columns(winner)?)
    let risen = _learn(env, learning, watching, winner, pattern, before)?

    _boosting(env, learning)?

    if not _still_unlearned(env, watching, winner, before)? then return 1 end
    if risen > 0 then 0 else 1 end

  fun _represent(env: Env, learning: SpatialPooler, pattern: Array[USize]): USize ? =>
    """
    The pattern as the pooler sees it before anything has been learned, and the
    column whose connections the rest of the example follows.
    """
    let winners = learning.compute(_input(pattern), false)?
    env.out.print("the pattern is represented by columns " + _columns(winners))

    let winner = winners(0)?

    env.out.print("")
    env.out.print("column " + winner.string() + " before learning:")
    _show(env, learning.columns(winner)?, _input(pattern))

    winner

  fun _learn(
    env: Env,
    learning: SpatialPooler,
    watching: SpatialPooler,
    winner: USize,
    pattern: Array[USize],
    before: Array[F64]): USize ?
  =>
    """
    Sixty rounds of one pooler learning and the other only looking, then what
    moved: the winning column's connections, and how many of them grew.
    """
    // sixty rounds: the minimum duty cycles are worked out every fiftieth
    var round: USize = 0
    while round < 60 do
      learning.compute(_input(pattern), true)?
      watching.compute(_input(pattern), false)?
      round = round + 1
    end

    env.out.print("")
    env.out.print("column " + winner.string() + " after learning:")
    _show(env, learning.columns(winner)?, _input(pattern))

    let after = _permanences(learning.columns(winner)?)
    let risen = _count_risen(before, after)
    env.out.print(risen.string() + " of "
      + before.size().string() + " connections grew towards the input")

    risen

  fun _boosting(env: Env, learning: SpatialPooler) ? =>
    """
    The columns that keep losing, and the help they are being given.
    """
    let helped = _boosted(learning)

    env.out.print("")
    env.out.print(helped.size().string() + " columns are being helped towards winning")
    _show_boosted(env, learning, helped)?

    env.out.print("")
    if helped.size() > 0 then
      env.out.print("a column that keeps losing is boosted, so the population does not")
      env.out.print("collapse onto whichever columns happened to win first")
    else
      env.out.print("no column needed help in these sixty rounds")
    end

  fun _show_boosted(env: Env, learning: SpatialPooler, helped: Array[USize]) ? =>
    var shown: USize = 0
    while shown < helped.size() do
      let column = helped(shown)?
      if shown < 6 then
        env.out.print("  column " + _pad(column.string(), 3)
          + " boost " + _near(learning.boost_factor(column)?))
      end
      shown = shown + 1
    end

  fun _still_unlearned(
    env: Env,
    watching: SpatialPooler,
    winner: USize,
    before: Array[F64]): Bool ?
  =>
    """
    A round without learning changes nothing, so the same input always gives the
    same representation.
    """
    env.out.print("")

    let first = watching.compute(_input(_pattern()), false)?
    let second = watching.compute(_input(_pattern()), false)?

    let unchanged =
      _same(first, second)
        and _same_floats(before, _permanences(watching.columns(winner)?))

    if unchanged then
      env.out.print(
        "the pooler that only watched is unchanged: inferences do not learn")
    else
      env.out.print("a round without learning changed the pooler")
    end

    unchanged

  fun _pattern(): Array[USize] => [3; 9; 14; 18; 25; 33; 41; 52]

  fun _input(bits: ReadSeq[USize], width: USize = 64): Array[Bool] =>
    let values = Array[Bool].init(false, width)
    for index in bits.values() do
      try values(index)? = true end
    end
    values

  fun _permanences(column: Column): Array[F64] =>
    let values = Array[F64]
    for synapse in column.synapses.values() do
      values.push(synapse.permanence)
    end
    values

  fun _show(env: Env, column: Column, input: ReadSeq[Bool]) =>
    """
    The connections that count, and how strongly the column believes in them.
    """
    for synapse in column.synapses.values() do
      if synapse.permanence > 0.0 then
        let state = try if input(synapse.input)? then "on " else "off" end else "?" end
        env.out.print("  input " + _pad(synapse.input.string(), 3)
          + state + "  permanence " + _near(synapse.permanence))
      end
    end

  fun _count_risen(before: ReadSeq[F64], after: ReadSeq[F64]): USize =>
    var risen: USize = 0
    try
      var index: USize = 0
      while index < after.size() do
        if after(index)? > before(index)? then risen = risen + 1 end
        index = index + 1
      end
    end
    risen

  fun _boosted(pooler: SpatialPooler): Array[USize] =>
    let helped = Array[USize]
    try
      var index: USize = 0
      while index < pooler.size() do
        if pooler.boost_factor(index)? > 1.0 then helped.push(index) end
        index = index + 1
      end
    end
    helped

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

  fun _same_floats(left: ReadSeq[F64], right: ReadSeq[F64]): Bool =>
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

  fun _near(value: F64): String =>
    """
    Two decimals are all a permanence needs to be read.
    """
    ((value * 100.0).round() / 100.0).string()
