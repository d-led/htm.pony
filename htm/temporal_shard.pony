use "collections"

interface TemporalSink
  """
  Where a shard reports. A shard never names who is listening, so it can be
  tested against any sink and the region is only one of them.
  """
  be activated(cells: Array[USize] val, bursting: Array[USize] val)
  be predicted(cells: Array[USize] val)

actor TemporalColumnShard
  """
  A band of temporal columns that share one actor.

  The shard owns its columns outright: nothing outside can reach their segments,
  so the memory's state is split between shards rather than copied, and no two
  actors can be writing the same column.

  It answers twice per round, and has to. `activate` decides the cells of the
  step and learns from the decision. `predict` says which cells the new state
  makes it expect, and that state includes what every other column did, so it
  cannot be answered in the same breath.
  """
  let _columns: Array[TemporalColumn] ref

  new create(first: USize, count: USize, params: TemporalMemoryParams val) =>
    let columns = Array[TemporalColumn](count)
    var index: USize = 0
    while index < count do
      columns.push(TemporalColumn(first + index, params))
      index = index + 1
    end
    _columns = columns

  be activate(
    previous: Array[Bool] val,
    previous_cells: Array[USize] val,
    incoming: Array[USize] val,
    learn: Bool,
    when: U64,
    sink: TemporalSink tag)
  =>
    let active: Array[USize] iso = recover iso Array[USize] end
    let bursting: Array[USize] iso = recover iso Array[USize] end

    for column in _columns.values() do
      let answer = column.activate(
        previous, previous_cells, _holds(incoming, column.index), learn, when)

      for cell in answer.cells.values() do
        active.push(cell)
      end
      if answer.burst then bursting.push(column.index) end
    end

    sink.activated(consume active, consume bursting)

  be predict(state: Array[Bool] val, sink: TemporalSink tag) =>
    let predictive: Array[USize] iso = recover iso Array[USize] end

    for column in _columns.values() do
      for cell in column.predict(state).values() do
        predictive.push(cell)
      end
    end

    sink.predicted(consume predictive)

  fun _holds(columns: ReadSeq[USize], column: USize): Bool =>
    for one in columns.values() do
      if one == column then return true end
    end
    false
