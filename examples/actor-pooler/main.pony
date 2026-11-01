use "../../htm"

primitive Session
  """
  The session both paths run: one pattern, sixty learning rounds of it, and one
  seed for the wiring.
  """
  fun rounds(): USize => 60

  fun seed(): U64 => 42

  fun config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64], false, 2.0)

  fun input(): Array[Bool] val =>
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end
    let bits: Array[USize] = [3; 5; 8; 13; 21; 44]
    try
      for index in bits.values() do
        values(index)? = true
      end
    end
    consume values

actor Main
  """
  The same spatial pooler running on actors, round for round.

  Wires four shards of sixteen columns, hands them to a `Pooler`, and runs the
  same sixty learning rounds on it and on an in-process `SpatialPooler` built
  from the same seed. It prints what each path answers at the first round and at
  the last, and whether the two agreed on every round between them.
  """
  let _env: Env
  let _expected: Array[Array[USize] val] val
  var _agreed: Bool = true

  new create(env: Env) =>
    _env = env
    _expected = _in_process()

    try
      let config = Session.config()
      let input = Session.input()
      let pooler = Pooler(
        PoolerShards.build(config, Session.seed(), 16)?,
        Grid(config.column_dimensions)?,
        config)

      pooler.represent(input, true, Listener(this, pooler, input))
    else
      _env.out.print("the example failed")
      _env.exitcode(1)
    end

  be answered(round: USize, active: Array[USize] val) =>
    let mine = _expected_at(round - 1)
    if not _same(mine, active) then _agreed = false end

    let last = Session.rounds()
    if (round == 1) or (round == last) then
      _env.out.print("round " + round.string() + " in process: " + _columns(mine))
      _env.out.print("round " + round.string() + " on actors:  " + _columns(active))
    end

    if round < last then return end

    if _agreed then
      _env.out.print("the two paths agreed on all "
        + Session.rounds().string() + " learning rounds")
      _env.exitcode(0)
    else
      _env.out.print("the two paths disagree")
      _env.exitcode(1)
    end

  fun tag _in_process(): Array[Array[USize] val] val =>
    let answers: Array[Array[USize] val] iso =
      recover iso Array[Array[USize] val] end

    try
      let pooler = SpatialPooler(Session.config(), Session.seed())?
      var round: USize = 0
      while round < Session.rounds() do
        answers.push(_frozen(pooler.compute(Session.input(), true)?))
        round = round + 1
      end
    end

    consume answers

  fun _expected_at(round: USize): Array[USize] val =>
    try _expected(round)? else recover val Array[USize] end end

  fun tag _frozen(values: ReadSeq[USize]): Array[USize] val =>
    let copy: Array[USize] iso = recover iso Array[USize] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

  fun tag _same(left: ReadSeq[USize], right: ReadSeq[USize]): Bool =>
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

  fun tag _columns(values: ReadSeq[USize]): String =>
    var text: String = ""
    for value in values.values() do
      if text.size() > 0 then text = text + ", " end
      text = text + value.string()
    end
    "[" + text + "]"

actor Listener is Representation
  """
  Hands each answer to the example and asks for the next round.
  """
  let _main: Main
  let _pooler: Pooler
  let _input: Array[Bool] val
  var _round: USize = 0

  new create(main: Main, pooler: Pooler, input: Array[Bool] val) =>
    _main = main
    _pooler = pooler
    _input = input

  be represented(active: Array[USize] iso) =>
    _round = _round + 1
    _main.answered(_round, consume active)

    if _round < Session.rounds() then
      _pooler.represent(_input, true, this)
    end
