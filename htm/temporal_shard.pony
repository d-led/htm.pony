use "collections"

interface TemporalSink
  """
  Where a shard reports. A shard never names who is listening, so it can be
  tested against any sink and the region is only one of them.

  Each answer names the band that gave it, which is how the collector tells a
  band that answered from one that stayed silent - and so which ones to ask
  again.
  """
  be activated(band: USize, cells: Array[USize] val, bursting: Array[USize] val)
  be predicted(band: USize, cells: Array[USize] val)

interface TemporalBand
  """
  A band of columns, as a region asks it: one pass of one round at a time, and
  answering into whatever sink it was handed.

  The region names this and not the shard actor, so any band can sit behind it -
  which is how a test proves the deadline with a band that never answers.
  """
  be take(band: USize, pass: TemporalPass val, sink: TemporalSink tag)

actor TemporalColumnShard is TemporalBand
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

  be take(band: USize, pass: TemporalPass val, sink: TemporalSink tag) =>
    """
    Answer one pass of one round: activate the step, or predict from the state
    the last pass produced.

    One entry point rather than two, because a pass is a value a collector can
    hand over again - that is what the retry after a deadline does - and the
    shard then answers the same question twice rather than having to remember
    what it was asked the first time.
    """
    if pass.predicting then
      let predictive: Array[USize] iso = recover iso Array[USize] end
      for column in _columns.values() do
        for cell in column.predict(pass.previous).values() do
          predictive.push(cell)
        end
      end
      sink.predicted(band, consume predictive)
    else
      let active: Array[USize] iso = recover iso Array[USize] end
      let bursting: Array[USize] iso = recover iso Array[USize] end

      for column in _columns.values() do
        let answer = column.activate(
          pass.previous,
          pass.previous_cells,
          _holds(pass.incoming, column.index),
          pass.learn,
          pass.when)

        for cell in answer.cells.values() do
          active.push(cell)
        end
        if answer.burst then bursting.push(column.index) end
      end

      sink.activated(band, consume active, consume bursting)
    end

  fun _holds(columns: ReadSeq[USize], column: USize): Bool =>
    for one in columns.values() do
      if one == column then return true end
    end
    false
