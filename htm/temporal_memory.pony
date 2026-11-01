use "collections"

class TemporalMemory
  """
  Learns which columns follow which, and predicts them.

  The spatial pooler answers "what is this". This answers "what comes next": it
  takes the active columns of one step, compares them with what it remembers
  about the step before, and says which cells it expects to be active at the
  next one.

  A column holds several cells so that one column can stand for more than one
  situation. If a column was predicted, only the cells that were predicted
  become active. If it was not, every cell in the column becomes active - it
  bursts - and the memory has to pick a cell to learn with.

  Learning is on the segments, not on the columns: a segment that predicted
  correctly has its synapses moved towards the cells that were actually there.
  """
  let params: TemporalMemoryParams val
  let _segments: Array[Array[TemporalSegment]]
  var _previous: Array[Bool]
  var _step: U64 = 0

  new create(params': TemporalMemoryParams val) =>
    params = params'

    let count = params'.cells()
    let segments = Array[Array[TemporalSegment]](count)
    var cell: USize = 0
    while cell < count do
      segments.push(Array[TemporalSegment])
      cell = cell + 1
    end

    _segments = segments
    _previous = Array[Bool].init(false, count)

  fun cells(): USize => params.cells()

  fun ref compute(active_columns: ReadSeq[USize], learn: Bool): TemporalOutput ? =>
    """
    One step. `active_columns` is what the spatial pooler answered. Fails on a
    column the memory was not built for.
    """
    _step = _step + 1

    let active = Array[Bool].init(false, cells())
    let bursting: Array[USize] iso = recover iso Array[USize] end
    let predicted_now = _predictive(_previous)

    for column in active_columns.values() do
      if column >= params.columns then error end

      let predicted_cells = _predicted_in(column, predicted_now)

      if predicted_cells.size() > 0 then
        for cell in predicted_cells.values() do
          try active(cell)? = true end
        end
        if learn then
          for cell in predicted_cells.values() do
            _reinforce_cell(cell)?
          end
        end
      else
        bursting.push(column)
        for cell in _cells_in(column).values() do
          try active(cell)? = true end
        end
        if learn then _learn_burst(column)? end
      end
    end

    _previous = active

    TemporalOutput(_indexes(active), _indexes(_predictive(active)), consume bursting)

  fun _predictive(state: ReadSeq[Bool]): Array[Bool] =>
    """
    The cells with at least one segment that matches the given active cells well
    enough to count as a prediction.
    """
    let predictive = Array[Bool].init(false, cells())
    var cell: USize = 0
    while cell < cells() do
      try
        for segment in _segments(cell)?.values() do
          if segment.matching(state, params.connected_threshold) >= params.activation_threshold
          then
            predictive(cell)? = true
            break
          end
        end
      end
      cell = cell + 1
    end
    predictive

  fun _predicted_in(column: USize, predictive: ReadSeq[Bool]): Array[USize] =>
    let result = Array[USize]
    for cell in _cells_in(column).values() do
      try
        if predictive(cell)? then result.push(cell) end
      end
    end
    result

  fun _cells_in(column: USize): Array[USize] =>
    let result = Array[USize](params.cells_per_column)
    var index: USize = 0
    while index < params.cells_per_column do
      result.push((column * params.cells_per_column) + index)
      index = index + 1
    end
    result

  fun ref _reinforce_cell(cell: USize) ? =>
    for segment in _segments(cell)?.values() do
      if segment.matching(_previous, params.connected_threshold) >= params.activation_threshold
      then
        _reinforce(segment)
      end
    end

  fun ref _reinforce(segment: TemporalSegment) =>
    segment.strengthen(
      _previous, params.permanence_increment, params.permanence_decrement)
    segment.connect_to(
      _previous_active_cells(), params.initial_permanence, params.max_synapses)
    segment.prune()
    segment.last_used = _step

  fun ref _learn_burst(column: USize) ? =>
    """
    A column that was not predicted learns a new segment for the situation that
    preceded it, or reinforces the segment that came closest.
    """
    match _best_segment(column)?
    | let segment: TemporalSegment => _reinforce(segment)
    | None =>
      let target = (column * params.cells_per_column)
      let segments = _segments(target)?
      if segments.size() < params.max_segments_per_cell then
        let segment = TemporalSegment(target)
        segment.connect_to(
          _previous_active_cells(), params.initial_permanence, params.max_synapses)
        segment.last_used = _step
        segments.push(segment)
      end
    end

  fun ref _best_segment(column: USize): (TemporalSegment | None) ? =>
    """
    The segment in this column that matches the previous step best, if any
    segment matches it at all.
    """
    var best: (TemporalSegment | None) = None
    var best_match: USize = 0

    for cell in _cells_in(column).values() do
      for segment in _segments(cell)?.values() do
        let matching = segment.matching(_previous, params.connected_threshold)
        if matching > best_match then
          best_match = matching
          best = segment
        end
      end
    end

    best

  fun _previous_active_cells(): Array[USize] val =>
    _indexes(_previous)

  fun _indexes(state: ReadSeq[Bool]): Array[USize] val =>
    let result: Array[USize] iso = recover iso Array[USize] end
    var index: USize = 0
    while index < state.size() do
      try
        if state(index)? then result.push(index) end
      end
      index = index + 1
    end
    consume result
