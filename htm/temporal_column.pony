use "collections"

class val ColumnStep
  """
  What one column did in one step: the cells it activated, which of them won,
  and whether it had to burst because nothing predicted it.

  The winner is one cell an active column, and it is a different thing from the
  cells that are active. A prediction activates the cell whose segment reached;
  a burst activates every cell and then picks one to be the cell the situation
  belongs to. The next step learns from the winners, not from every cell that
  happened to be on - that is what keeps a segment reaching the cells that will
  be active next time rather than half of them.
  """
  let cells: Array[USize] val
  let winners: Array[USize] val
  let burst: Bool

  new val create(
    cells': Array[USize] val,
    winners': Array[USize] val,
    burst': Bool)
  =>
    cells = cells'
    winners = winners'
    burst = burst'

class TemporalColumn
  """
  One column's cells, and what they have learned.

  A column is the unit of state in a temporal memory. Everything a column
  computes depends on the previous step's active cells and on its own segments,
  and on nothing that belongs to another column. That is what lets the same
  computation run over an array of these objects in one process, or over a
  shard of actors holding slices of that array, and give the same answer.

  Nothing here can fail: a column's cells are its own, and its segments are
  indexed by them. An actor cannot report an error anyway, so the choice is
  between operations that always answer and a branch that pretends.
  """
  let index: USize
  let _params: TemporalMemoryParams val
  let _segments: Array[Array[TemporalSegment]]
  let _first_cell: Array[TemporalSegment]

  new create(index': USize, params: TemporalMemoryParams val) =>
    index = index'
    _params = params

    let first = Array[TemporalSegment]
    let per_cell = Array[Array[TemporalSegment]](params.cells_per_column)

    var offset: USize = 0
    while offset < params.cells_per_column do
      if offset == 0 then
        per_cell.push(first)
      else
        per_cell.push(Array[TemporalSegment])
      end
      offset = offset + 1
    end

    _first_cell = first
    _segments = per_cell

  fun cells(): Array[USize] =>
    """
    The cells this column owns, by their name in the whole memory.
    """
    let result = Array[USize](_params.cells_per_column)
    var offset: USize = 0
    while offset < _params.cells_per_column do
      result.push(_cell_at(offset))
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
      if _enough(segments, state) then
        result.push(_cell_at(offset))
      end
    end
    consume result

  fun ref activate(
    previous: ReadSeq[Bool],
    previous_winners: ReadSeq[USize],
    active: Bool,
    learn: Bool,
    when: U64): ColumnStep
  =>
    """
    Decide this column's cells for the step, and learn from the decision.

    A column that is not active activates nothing, but it still answers for its
    own mistakes: a segment that predicted and had its cell then miss is
    weakened whether or not the column was in the input.
    """
    let predicting = _matching(previous)
    var activated: Array[USize] val = recover val Array[USize] end
    var winners: Array[USize] val = recover val Array[USize] end
    var burst = false

    if active then
      let predicted = predict(previous)

      if predicted.size() > 0 then
        activated = predicted
        winners = predicted
        if learn then _reinforce_predicting(previous, previous_winners, when) end
      else
        burst = true
        let everywhere: Array[USize] iso = recover iso Array[USize] end
        for cell in cells().values() do
          everywhere.push(cell)
        end
        activated = consume everywhere

        let chosen = _win(previous, previous_winners, learn, when)
        let one: Array[USize] iso = recover iso Array[USize] end
        one.push(chosen)
        winners = consume one
      end
    end

    if learn then _punish(predicting, activated, previous) end

    ColumnStep(activated, winners, burst)

  fun ref _win(
    previous: ReadSeq[Bool],
    previous_winners: ReadSeq[USize],
    learn: Bool,
    when: U64): USize
  =>
    """
    Which cell a burst belongs to: the owner of the segment that came closest,
    or the first cell, where a new segment is grown.

    One cell, not every cell the burst lit up. The next step grows synapses to
    this cell, so it has to be the cell a prediction will activate again.
    """
    match _best_segment(previous)
    | let segment: TemporalSegment =>
      if learn then _reinforce(segment, previous, previous_winners, when) end
      segment.owner
    | None =>
      if
        learn and (_first_cell.size() < _params.max_segments_per_cell)
      then
        let segment = TemporalSegment(_cell_at(0))
        segment.connect_to(
          previous_winners, _params.initial_permanence, _params.max_synapses)
        segment.last_used = when
        _first_cell.push(segment)
      end
      _cell_at(0)
    end

  fun _enough(segments: ReadSeq[TemporalSegment], state: ReadSeq[Bool]): Bool =>
    """
    Whether any of these segments matches the state well enough to predict.
    """
    for segment in segments.values() do
      if _reaches(segment, state) then return true end
    end
    false

  fun _reaches(segment: TemporalSegment box, state: ReadSeq[Bool]): Bool =>
    segment.matching(state, _params.connected_threshold) >= _params.activation_threshold

  fun ref _matching(state: ReadSeq[Bool]): Array[TemporalSegment] =>
    """
    The segments of this column that are sure enough to be a prediction.
    """
    let result = Array[TemporalSegment]
    for segments in _segments.values() do
      for segment in segments.values() do
        if _reaches(segment, state) then
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

  fun ref _reinforce_predicting(
    previous: ReadSeq[Bool],
    previous_winners: ReadSeq[USize],
    when: U64)
  =>
    """
    A cell that was predicted and did activate keeps what it predicted with.
    """
    for segments in _segments.values() do
      if _enough(segments, previous) then
        for segment in segments.values() do
          if _reaches(segment, previous) then
            _reinforce(segment, previous, previous_winners, when)
          end
        end
      end
    end

  fun ref _reinforce(
    segment: TemporalSegment,
    previous: ReadSeq[Bool],
    previous_winners: ReadSeq[USize],
    when: U64)
  =>
    """
    Keep a segment that was right, and reach towards the cells that won.

    New synapses go to the previous step's winners and not to every cell that was
    active. A burst lights up every cell of its column, so reaching all of them
    and then being capped at `max_synapses` would wire the segment to a mix of
    the two offsets - half of it wrong the moment the state arrives as a
    prediction rather than a burst.
    """
    segment.strengthen(
      previous, _params.permanence_increment, _params.permanence_decrement)
    segment.connect_to(
      previous_winners, _params.initial_permanence, _params.max_synapses)
    segment.prune()
    segment.last_used = when

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

  fun _holds(activated: ReadSeq[USize], cell: USize): Bool =>
    for one in activated.values() do
      if one == cell then return true end
    end
    false
