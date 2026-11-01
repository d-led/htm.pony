use "../../htm"
use "random"

actor Main
  """
  The same spatial pooler running on actors.

  Wires four shards of sixteen columns, hands them to a `Pooler`, asks for a
  representation, and prints it. The in-process pooler is built from the same
  seed so the two answers can be compared.
  """
  let _env: Env
  let _expected: Array[USize] val

  new create(env: Env) =>
    _env = env
    _expected = _in_process()
    _env.out.print("in process: " + _columns(_expected))

    try
      let pooler = Pooler(_shards()?, Grid([8; 8])?, _config())
      pooler.represent(_input(), Listener(this))
    else
      _env.out.print("the example failed")
      _env.exitcode(1)
    end

  fun tag _config(): SpatialPoolerConfig val =>
    SpatialPoolerConfig([8; 8], [64], false, 2.0)

  fun tag _in_process(): Array[USize] val =>
    try
      return _frozen_columns(SpatialPooler(_config(), 42)?.compute(_input())?)
    else
      return recover val Array[USize] end
    end

  be answered(active: Array[USize] iso) =>
    let received: Array[USize] val = consume active
    _env.out.print("on actors:  " + _columns(received))

    if _same(_expected, received) then
      _env.out.print("both paths give the same representation")
      _env.exitcode(0)
    else
      _env.out.print("the two paths disagree")
      _env.exitcode(1)
    end

  fun tag _input(): Array[Bool] val =>
    let values: Array[Bool] iso = recover iso Array[Bool].init(false, 64) end
    let bits: Array[USize] = [3; 5; 8; 13; 21; 44]
    try
      for index in bits.values() do
        values(index)? = true
      end
    end
    consume values

  fun tag _shards(): Array[ColumnShard tag] val ? =>
    """
    Four bands of sixteen columns, wired as `SpatialPooler` wires its own:
    columns in order, from one seeded generator.

    A shard shares its synapses between actors, so the wiring is frozen into a
    value before it is handed over.
    """
    let config = _config()
    let random = Rand(42)
    let inputs = Grid(config.input_dimensions)?
    let shards: Array[ColumnShard tag] iso = recover iso Array[ColumnShard tag] end

    var first: USize = 0
    while first < config.num_columns() do
      let views: Array[ColumnView] iso = recover iso Array[ColumnView] end

      var column = first
      while (column < (first + 16)) and (column < config.num_columns()) do
        let wired = Wiring.synapses(config, inputs, random, column)?
        views.push(ColumnView(column, _frozen_synapses(wired)))
        column = column + 1
      end

      shards.push(ColumnShard(consume views, config.connection_threshold))
      first = first + 16
    end

    consume shards

  fun tag _frozen_synapses(values: ReadSeq[Synapse]): Array[Synapse] val =>
    let copy: Array[Synapse] iso = recover iso Array[Synapse] end
    for value in values.values() do
      copy.push(value)
    end
    consume copy

  fun tag _frozen_columns(values: ReadSeq[USize]): Array[USize] val =>
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
  Receives the representation and hands it back to the example.
  """
  let _main: Main

  new create(main: Main) =>
    _main = main

  be represented(active: Array[USize] iso) =>
    _main.answered(consume active)
