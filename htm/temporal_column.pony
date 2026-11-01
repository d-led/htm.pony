use "collections"

class val ColumnStep
  """
  What one column did in one step: the cells it activated, and whether it had to
  burst because nothing predicted it.
  """
  let cells: Array[USize] val
  let burst: Bool

  new val create(cells': Array[USize] val, burst': Bool) =>
    cells = cells'
    burst = burst'

class TemporalColumn
  """
  One column's cells, and what they have learned.

  A column is the unit of state in a temporal memory. Everything a column
  computes depends on the previous step's active cells and on its own segments,
  and on nothing that belongs to another column. That is what lets the same
  computation run over an array of these objects in one process, or over a
  shard of actors holding slices of that array, and give the same answer.
  """
  let index: USize
  let _params: TemporalMemoryParams val
  let _segments: Array[Array[TemporalSegment]]

  new create(index': USize, params: TemporalMemoryParams val) =>
    index = index'
    _params = params

    let per_cell = Array[Array[TemporalSegment]](params.cells_per_column)
    var offset: USize = 0
    while offset < params.cells_per_column do
      per_cell.push(Array[TemporalSegment])
      offset = offset + 1
    end
    _segments = per_cell

  fun cells(): Array[USize] =>
    """
    The cells this column owns, by their name in the whole memory.
    """
    let result = Array[USize](_params.cells_per_column)
    var offset: USize = 0
    while offset < _params.cells_per_column do
      result.push((index * _params.cells_per_column) + offset)
      offset = offset + 1
    end
    result

  fun predict(state: ReadSeq[Bool]): Array[USize] val =>
    """
    The cells of this column a segment expects to be active next, given the
    state now.
    """
    let result: Array[USize] iso = recover iso Array[USize] end
    for (offset, segments) in _segments.pairs() do
      for segment in segments.values() do
        if segment.matching(state, _params.connected_threshold) >= _params.activation_threshold
        then
          result.push(_cell_at(offset))
          break
        end
      end
    end
    consume result

  fun ref activate(
    previous: ReadSeq[Bool],
    previous_cells: ReadSeq[USize],
    active: Bool,
    learn: Bool,
    when: U64): ColumnStep ?
  =>
    """
    Decide this column's cells for the step, and learn from the decision.

    A column that is not active activates nothing, but it still answers for its
    own mistakes: a segment that predicted and had its cell then miss is
    weakened whether or not the column was in the input.
    """
    let predicting = _matching(previous)
    var activated: Array[USize] val = recover val Array[USize] end
    var burst = false

    if active then
      let predicted = predict(previous)

      if predicted.size() > 0 then
        activated = predicted
        if learn then
          for cell in predicted.values() do
            _reinforce_cell(cell, previous, previous_cells, when)?
          end
        end
      else
        burst = true
        let everywhere: Array[USize] iso = recover iso Array[USize] end
        for cell in cells().values() do
          everywhere.push(cell)
        end
        activated = consume everywhere
        if learn then _learn_burst(previous, previous_cells, when)? end
      end
    end

    if learn then _punish(predicting, activated, previous) end

    ColumnStep(activated, burst)

  fun ref _matching(state: ReadSeq[Bool]): Array[TemporalSegment] =>
    """
    The segments of this column that are sure enough to be a prediction.
    """
    let result = Array[TemporalSegment]
    for segments in _segments.values() do
      for segment in segments.values() do
        if segment.matching(state, _params.connected_threshold) >= _params.activation_threshold
        then
          result.push(segment)
        end
      end
    end
    result

  fun ref _punish(
    predicting: Array[TemporalSegment],
    activated: ReadSeq[USize],
    previous: ReadSeq[Bool])
  =>
    """
    A segment that predicted, on a cell that then did not activate, was wrong.
    """
    for segment in predicting.values() do
      if not _holds(activated, segment.owner) then
        segment.weaken(previous, _params.permanence_decrement)
        segment.prune()
      end
    end

  fun ref _reinforce_cell(
    cell: USize,
    previous: ReadSeq[Bool],
    previous_cells: ReadSeq[USize],
    when: U64) ?
  =>
    for segment in _segments(_offset_of(cell))?.values() do
      if segment.matching(previous, _params.connected_threshold) >= _params.activation_threshold
      then
        _reinforce(segment, previous, previous_cells, when)
      end
    end

  fun ref _reinforce(
    segment: TemporalSegment,
    previous: ReadSeq[Bool],
    previous_cells: ReadSeq[USize],
    when: U64)
  =>
    segment.strengthen(
      previous, _params.permanence_increment, _params.permanence_decrement)
    segment.connect_to(
      previous_cells, _params.initial_permanence, _params.max_synapses)
    segment.prune()
    segment.last_used = when

  fun ref _learn_burst(
    previous: ReadSeq[Bool],
    previous_cells: ReadSeq[USize],
    when: U64) ?
  =>
    """
    A column nothing predicted learns the situation that preceded it: on the
    segment that came closest, or on a new segment of its first cell.
    """
    match _best_segment(previous)
    | let segment: TemporalSegment => _reinforce(segment, previous, previous_cells, when)
    | None =>
      let segments = _segments(0)?
      if segments.size() < _params.max_segments_per_cell then
        let segment = TemporalSegment(cells()(0)?)
        segment.connect_to(
          previous_cells, _params.initial_permanence, _params.max_synapses)
        segment.last_used = when
        segments.push(segment)
      end
    end

  fun ref _best_segment(previous: ReadSeq[Bool]): (TemporalSegment | None) =>
    var best: (TemporalSegment | None) = None
    var best_match: USize = 0

    for segments in _segments.values() do
      for segment in segments.values() do
        let matching = segment.matching(previous, _params.connected_threshold)
        if matching > best_match then
          best_match = matching
          best = segment
        end
      end
    end

    best

  fun _cell_at(offset: USize): USize =>
    (index * _params.cells_per_column) + offset

  fun _offset_of(cell: USize): USize =>
    cell - (index * _params.cells_per_column)

  fun _holds(activated: ReadSeq[USize], cell: USize): Bool =>
    for one in activated.values() do
      if one == cell then return true end
    end
    false
