use "random"

class TemporalPooler
  """
  A CLA temporal pooler in one process: the cells, what they remember, and the
  step that reads one pattern and predicts the next.

  It differs from `TemporalMemory` in what a state is. A temporal memory bursts a
  column into all of its cells and learns from the previous step; a pooler also
  learns from the step before *that* when a cell is still being predicted, so the
  state it settles on is a union of the situations that led here rather than one
  path through them. That is what `TemporalPoolerConfig.pooling` turns on, and it
  is the next slice: what is here computes the same step the reference does with
  pooling off.

  Two things of the reference are not here yet, both written where they would go:
  the backtracking that re-plays a step from an earlier starting point when a
  sequence is lost, and the pooled representation itself. Without backtracking a
  lost sequence starts over on its start cells, which is what the reference does
  when backtracking finds nothing.
  """
  let _config: TemporalPoolerConfig val
  let _nodes: Array[ClaNode]
  let _learning: CellState
  let _inference: CellState
  let _confidence: CellConfidence
  let _rand: Rand
  var _updates: Array[ClaSegmentUpdate]
  var _learning_iteration: U64 = 0
  var _iteration: U64 = 0
  var _pam_counter: USize
  var _learned_sequence_length: USize = 0
  var _reset_called: Bool = false
  var _input_density: (F64 | None) = None

  new create(config': TemporalPoolerConfig val, seed: U64 = 42) =>
    """
    A pooler of the given shape. The seed decides which cell a column chooses
    when it has to learn on a new one, and which cells a segment reaches next;
    two poolers with the same seed and the same steps take the same decisions.
    """
    _config = config'

    let nodes = Array[ClaNode](config'.columns)
    var column: USize = 0
    while column < config'.columns do
      nodes.push(ClaNode(column, config'.cells_per_column))
      column = column + 1
    end
    _nodes = nodes

    _learning = CellState(config'.columns, config'.cells_per_column)
    _inference = CellState(config'.columns, config'.cells_per_column)
    _confidence = CellConfidence(config'.columns, config'.cells_per_column)
    _rand = Rand(seed)
    _updates = Array[ClaSegmentUpdate]
    _pam_counter = config'.pam_length

    // Pony's generator is weak for the first few draws after seeding: it tracks
    // the seed closely enough that a first choice would be decided by the seed
    // rather than by chance.
    var warming: USize = 0
    while warming < 16 do
      _rand.next()
      warming = warming + 1
    end

  fun cells(): USize =>
    """
    How many cells the pooler has.
    """
    _config.cells()

  fun ref segments(): USize =>
    """
    How many segments it has grown, over every cell.
    """
    var counted: USize = 0
    for node in _nodes.values() do
      for cell in node.cells().values() do
        counted = counted + cell.segments.size()
      end
    end
    counted

  fun active_cells(): Array[USize] =>
    """
    The cells the inference pass activated at the last step.
    """
    _inference.cells_in_state()

  fun predicted_cells(): Array[USize] =>
    """
    The cells the inference pass expects at the next step.
    """
    _inference.predicted_cells()

  fun predicted_columns(): Array[USize] =>
    """
    The nodes the inference pass expects to receive input at the next step.
    """
    let found = Array[USize]
    let seen = Array[Bool].init(false, _config.columns)

    for cell in _inference.predicted_cells().values() do
      let column = _config.node_of(cell)
      try
        if not seen(column)? then
          seen(column)? = true
          found.push(column)
        end
      end
    end

    found

  fun ref compute(
    active_columns: ReadSeq[USize],
    learn: Bool,
    infer: Bool): Array[USize] ?
  =>
    """
    One step: read the columns that received input, learn if asked, and answer
    with the cells that are active or predicted.

    At least one of learning and inferring has to be asked for; a step that does
    neither would return the state of the step before as if it were new.
    """
    if not (learn or infer) then error end

    if learn then
      _learning_iteration = _learning_iteration + 1
      if ClaDutyCycle.is_a_boundary(_learning_iteration) then
        _review_duty_cycles()
      end
    end
    _iteration = _iteration + 1

    _track_density(active_columns.size())

    if infer then _update_inference(active_columns) end

    if learn then
      _update_learning(active_columns)
      _decay_if_due()
    end

    let output = _output()
    _reset_called = false
    output

  fun ref reset() =>
    """
    Forget the situation, keeping what has been learned. This is what separates
    one training sequence from the next: the next step is not a continuation of
    anything, so it starts on the start cells.
    """
    _learning.clear_active()
    _learning.clear_predicted()
    _learning.clear_before()

    _inference.clear_active()
    _inference.clear_predicted()
    _inference.clear_before()

    _confidence.clear()
    _confidence.clear_before()

    _updates = Array[ClaSegmentUpdate]
    _reset_called = true

  // The inference pass ------------------------------------------------------
  //
  // Inference answers two questions in order: which cells are active, given the
  // input and what was predicted, and which cells does that make predicted next.

  fun ref _update_inference(active_columns: ReadSeq[USize]) =>
    _inference.advance()
    _confidence.advance()

    // The reference re-plays the step from an earlier starting point when the
    // input was not predicted. That backtracking is not ported yet, so an
    // unpredicted step bursts and inference carries on from there.
    _infer_phase1(active_columns)
    _infer_phase2()

  fun ref _infer_phase1(active_columns: ReadSeq[USize]): Bool =>
    """
    Decide the active cells: the predicted ones where there are any, the whole
    node where there are none. After a reset nothing is predicted into the step,
    so every node starts on its start cell.
    """
    _inference.clear_active()

    if _reset_called then
      for column in active_columns.values() do
        _inference.activate(_config.cell_of(column, 0))
      end
      return true
    end

    var matched_columns: USize = 0

    for column in active_columns.values() do
      let predicted = _inference.predicted_in_before(column)

      if predicted.size() > 0 then
        for offset in predicted.values() do
          _inference.activate(_config.cell_of(column, offset))
        end
        matched_columns = matched_columns + 1
      else
        var offset: USize = 0
        while offset < _config.cells_per_column do
          _inference.activate(_config.cell_of(column, offset))
          offset = offset + 1
        end
      end
    end

    matched_columns >= (active_columns.size() / 2)

  fun ref _infer_phase2() =>
    """
    Decide the prediction, and how sure the pooler is of each part of it.

    Every segment that reaches enough of the active state contributes its own
    record of how often it has been right, whether or not it is strong enough to
    predict: a weak match is still evidence.
    """
    _inference.clear_predicted()
    _confidence.clear()

    let state = _inference.active_bits()

    for node in _nodes.values() do
      for cell in node.cells().values() do
        let name = _config.cell_of(node.index, cell.offset)

        for segment in cell.segments.values() do
          if segment.activity(state) < _config.activation_threshold then
            continue
          end

          _confidence.credit(name, segment.duty_cycle(_learning_iteration, false))

          if segment.active(
            state, _config.activation_threshold, _config.connected_threshold)
          then
            _inference.predict(name)
          end
        end
      end
    end

    _confidence.share_out()

  // The learning pass -------------------------------------------------------

  fun ref _update_learning(active_columns: ReadSeq[USize]) =>
    """
    One learning step: judge the predictions queued last time, activate this
    step's cells, decide whether the sequence held, and predict ahead.
    """
    _learning.advance()
    _process_updates(active_columns)

    if _pam_counter > 0 then _pam_counter = _pam_counter - 1 end
    _learned_sequence_length = _learned_sequence_length + 1

    if not _reset_called then
      if _learn_phase1(active_columns) then
        _pam_counter = _config.pam_length
      end
    end

    if
      _reset_called
        or (_pam_counter == 0)
        or ((_config.max_sequence_length != 0)
          and (_learned_sequence_length >= _config.max_sequence_length))
    then
      _start_over(active_columns)
    end

    _learn_phase2()

  fun ref _learn_phase1(active_columns: ReadSeq[USize]): Bool =>
    """
    Activate the predicted cell of every node that received input, and teach the
    nodes that were not predicted.

    Answers whether enough of the input was predicted for the sequence to count
    as unbroken - half of it, as in the reference.
    """
    _learning.clear_active()
    var unpredicted: USize = 0

    let before = _learning.active_bits_before()

    for column in active_columns.values() do
      let predicted = _learning.predicted_in_before(column)

      if predicted.size() > 0 then
        try
          _learning.activate(_config.cell_of(column, predicted(0)?))
        end
        continue
      end

      unpredicted = unpredicted + 1

      let found = _best_matching_cell(column, before, _config.min_threshold)

      match found.segment
      | let segment: ClaSegment =>
        _learning.activate(_config.cell_of(column, found.offset))
        _apply(_synapses_for(column, found.offset, segment, before, true))
      | None =>
        let fresh = _cell_for_new_segment(column)
        _learning.activate(_config.cell_of(column, fresh))
        _apply(_synapses_for(column, fresh, None, before, true))
      end
    end

    unpredicted < (active_columns.size() / 2)

  fun ref _learn_phase2() =>
    """
    Predict ahead, and queue what each prediction would change.

    At most one cell of a node is predicted in the learning pass: the one whose
    best segment matches the active state. The proposal is queued rather than
    applied because whether it was right is only known when the next input
    arrives.
    """
    _learning.clear_predicted()

    let state = _learning.active_bits()
    let before = _learning.active_bits_before()
    var column: USize = 0

    while column < _config.columns do
      let found = _best_matching_cell(column, state, _config.activation_threshold)

      match found.segment
      | let segment: ClaSegment =>
        _learning.predict(_config.cell_of(column, found.offset))
        segment.total = segment.total + 1

        let reach_more = found.activity < _config.new_synapse_count
        let update = _synapses_for(column, found.offset, segment, state, reach_more)
        if update.proposed() then _updates.push(update) end

        if _config.pooling then
          _queue_pooling(column, found.offset, before)
        end
      | None => None
      end

      column = column + 1
    end

  fun ref _queue_pooling(column: USize, offset: USize, before: ReadSeq[Bool]) =>
    """
    Queue what this cell would learn from the step *before* the one that
    predicted it.

    This is what makes the pooler a CLA rather than a sequence memory. A cell
    that predicted also learns the situation one step further back, on the
    segment of its node that matches that step - so the state it settles on is
    the union of the situations that led here, rather than a single path. The
    reference creates a segment for the older situation when no segment of the
    node matches it.
    """
    match _cell_of(column, offset)
    | let cell: ClaCell =>
      let earlier = cell.best_segment(before, _config.min_threshold)
      let update = _synapses_for(column, offset, earlier, before, true)
      if update.proposed() then _updates.push(update) end
    end

  fun ref _process_updates(active_columns: ReadSeq[USize]) =>
    """
    Judge last step's proposals: apply the ones whose node received input in
    time, drop the rest.

    A proposal for a node that did not fire is not evidence, and is dropped -
    unless pooling is on and the cell is still being predicted, in which case it
    keeps its proposal for another step, as long as the window allows.
    """
    let pending = _updates
    let kept = Array[ClaSegmentUpdate]
    _updates = kept

    for update in pending.values() do
      if (_learning_iteration - update.when) > _config.update_window.u64() then
        continue
      end

      if _holds(active_columns, update.column) then
        _apply(update)
      elseif
        _config.pooling
          and _learning.predicted(_config.cell_of(update.column, update.offset))
      then
        // The cell is still being predicted, so what it would learn is still
        // worth learning - that is what the update window is for.
        kept.push(update)
      end
    end

  fun ref _start_over(active_columns: ReadSeq[USize]) =>
    """
    Begin a new sequence on the start cells.

    The reference first tries to backtrack into an earlier start cell, and only
    falls back to this. Until backtracking is ported, every lost sequence comes
    here.
    """
    _learning.clear_active()

    for column in active_columns.values() do
      _learning.activate(_config.cell_of(column, 0))
    end

    _pam_counter = _config.pam_length
    _learned_sequence_length = 0
    _updates = Array[ClaSegmentUpdate]

  // Applying a proposal -----------------------------------------------------

  fun ref _apply(update: ClaSegmentUpdate) =>
    """
    Teach the segment a proposal is about, or grow the segment it asks for.

    An existing segment is marked fresh, every synapse it has that did not reach
    an active cell is weakened, the ones that did are strengthened, and the cells
    it does not reach yet are connected. A segment that weakened to nothing is
    dropped.
    """
    match update.segment
    | let segment: ClaSegment =>
      segment.renew(update.when)

      let inactive = _inactive(segment, update.strengthen)
      let trimmed = segment.move(
        inactive, -_config.permanence_decrement, _config.permanence_max)
      segment.move(update.strengthen, _config.permanence_increment, _config.permanence_max)

      for source in update.reach.values() do
        segment.add_synapse(source, _config.initial_permanence)
      end

      if trimmed then
        match _cell_of(update.column, update.offset)
        | let cell: ClaCell => cell.trim(segment, 0.00001)
        end
      end
    | None =>
      // A cell learns a new situation from nothing. Without anything to reach
      // there is nothing to learn, so no empty segment is grown.
      if update.reach.size() == 0 then return end

      match _cell_of(update.column, update.offset)
      | let cell: ClaCell =>
        let segment = cell.new_segment(update.when)
        for source in update.reach.values() do
          segment.add_synapse(source, _config.initial_permanence)
        end
      end
    end

  fun ref _synapses_for(
    column: USize,
    offset: USize,
    segment: (ClaSegment | None),
    state: ReadSeq[Bool],
    reach_more: Bool): ClaSegmentUpdate
  =>
    """
    Work out what a segment should learn from one state: which of its synapses
    reach active cells, and which cells it should reach but does not.
    """
    let strengthen = Array[USize]

    match segment
    | let existing: ClaSegment =>
      var index: USize = 0
      while index < existing.synapses.size() do
        try
          let synapse = existing.synapses(index)?
          if state(synapse.source)? then strengthen.push(index) end
        end
        index = index + 1
      end
    | None => None
    end

    let reach = Array[USize]

    if reach_more then
      let wanted =
        if _config.new_synapse_count > strengthen.size() then
          _config.new_synapse_count - strengthen.size()
        else
          0
        end

      for source in _choose(segment, wanted, state).values() do
        reach.push(source)
      end
    end

    ClaSegmentUpdate(
      column,
      offset,
      segment,
      strengthen,
      reach,
      _learning_iteration)

  fun ref _choose(
    segment: (ClaSegment | None),
    wanted: USize,
    state: ReadSeq[Bool]): Array[USize]
  =>
    """
    Pick up to `wanted` active cells for a segment to reach, none of which it
    already reaches.

    All of them when there are no more than were asked for; otherwise one at
    random, or a random subset - which is what keeps two segments of the same
    cell from learning the same situation and becoming the same memory.
    """
    let candidates = Array[USize]
    if wanted == 0 then return candidates end

    var cell: USize = 0
    while cell < state.size() do
      try
        if state(cell)? then
          match segment
          | let existing: ClaSegment =>
            if not existing.reaches(cell) then candidates.push(cell) end
          | None =>
            candidates.push(cell)
          end
        end
      end
      cell = cell + 1
    end

    if candidates.size() <= wanted then return candidates end

    if wanted == 1 then
      let picked = Array[USize]
      try picked.push(candidates(_rand.int(candidates.size()))?) end
      return picked
    end

    // An inside-out shuffle: each candidate is swapped with one already placed,
    // so every permutation is equally likely and nothing beyond `wanted` is
    // touched.
    var placed: USize = 0
    while placed < candidates.size() do
      let other = _rand.int(placed + 1)
      try
        let held = candidates(placed)?
        candidates(placed)? = candidates(other)?
        candidates(other)? = held
      end
      placed = placed + 1
    end

    let chosen = Array[USize](wanted)
    var taken: USize = 0
    while taken < wanted do
      try chosen.push(candidates(taken)?) end
      taken = taken + 1
    end
    chosen

  // Reading the population ---------------------------------------------------

  fun ref _best_matching_cell(
    column: USize,
    state: ReadSeq[Bool],
    min_threshold: USize): ClaCellMatch
  =>
    """
    The cell of a node that matches best, the segment that makes it so, and how
    much of the state that segment reaches.

    Nothing at all when no cell reaches the threshold. The last cell to reach the
    best activity answers, which is the reference's rule for choosing where to
    learn.
    """
    var best_activity = min_threshold
    var best_offset: USize = 0
    var best_segment: (ClaSegment | None) = None

    match _node(column)
    | let node: ClaNode =>
      for cell in node.cells().values() do
        let strongest = cell.strongest(state)

        if (strongest._1 >= best_activity) and (cell.segments.size() > 0) then
          best_activity = strongest._1
          best_offset = cell.offset
          try best_segment = cell.segments(strongest._2)? end
        end
      end
    end

    ClaCellMatch(best_offset, best_segment, best_activity)

  fun ref _cell_for_new_segment(column: USize): USize =>
    """
    Which cell of a node should take a new segment.

    Any but the start cell: a start cell that also learned the interior of a
    sequence could not tell the beginning of one from the middle.
    """
    if _config.cells_per_column == 1 then return 0 end
    _rand.int(_config.cells_per_column - 1) + 1

  fun ref _node(column: USize): (ClaNode | None) =>
    try _nodes(column)? else None end

  fun ref _cell_of(column: USize, offset: USize): (ClaCell | None) =>
    if offset >= _config.cells_per_column then return None end
    match _node(column)
    | let node: ClaNode => try node.cells()(offset)? else None end
    | None => None
    end

  fun _inactive(segment: ClaSegment box, strengthened: ReadSeq[USize]): Array[USize] =>
    """
    The positions of the synapses a proposal does not name, which are the ones
    that did not reach an active cell.
    """
    let weakened = Array[USize]
    var index: USize = 0
    while index < segment.synapses.size() do
      if not _holds(strengthened, index) then weakened.push(index) end
      index = index + 1
    end
    weakened

  fun _holds(indices: ReadSeq[USize], index: USize): Bool =>
    for one in indices.values() do
      if one == index then return true end
    end
    false

  // Bookkeeping -------------------------------------------------------------

  fun ref _review_duty_cycles() =>
    """
    Bring every segment's record up to date at a tier boundary.

    The estimate is a moving average whose step depends on the tier, and it is
    only recomputed when asked; a segment never asked again would keep the step
    it was last asked with, so every one of them is asked here.
    """
    for node in _nodes.values() do
      for cell in node.cells().values() do
        for segment in cell.segments.values() do
          segment.duty_cycle(_learning_iteration, false)
        end
      end
    end

  fun ref _track_density(count: USize) =>
    match _input_density
    | let density: F64 =>
      _input_density = (0.99 * density) + (0.01 * count.f64())
    else
      _input_density = count.f64()
    end

  fun ref _decay_if_due() =>
    """
    Age every synapse of every segment that has not been used for a while.

    This happens rarely - once every `max_segment_age` learning steps - and takes
    away the connections nobody needed, which is what lets a pooler keep learning
    in data that drifts.
    """
    if _config.global_decay <= 0.0 then return end
    if _config.max_segment_age == 0 then return end
    if (_learning_iteration % _config.max_segment_age.u64()) != 0 then return end

    for node in _nodes.values() do
      for cell in node.cells().values() do
        let kept = Array[ClaSegment](cell.segments.size())

        for segment in cell.segments.values() do
          if segment.age(_learning_iteration) <= _config.max_segment_age.u64() then
            kept.push(segment)
            continue
          end

          segment.decay(_config.global_decay)
          if segment.synapses.size() > 0 then kept.push(segment) end
        end

        cell.replace(kept)
      end
    end

  fun ref _output(): Array[USize] =>
    """
    What the step answers with: every cell that is active or predicted.
    """
    let out = Array[USize]

    for node in _nodes.values() do
      for cell in node.cells().values() do
        let name = _config.cell_of(node.index, cell.offset)
        if _inference.active(name) or _inference.predicted(name) then
          out.push(name)
        end
      end
    end

    out
