// Follows temporalPooler.go in htm-community/htm (MIT) with this repository's
// structure. See docs/sources.md.
use "random"

class TemporalPooler
  """
  A CLA temporal pooler in one process: the cells, what they remember, and the
  step that reads one pattern and predicts the next.

  It differs from `TemporalMemory` in what a state is. A temporal memory bursts a
  column into all of its cells and learns from the previous step; a pooler also
  learns from the step before *that* when a cell is still being predicted, so the
  state it settles on is a union of the situations that led here rather than one
  path through them. That is what `TemporalPoolerConfig.pooling` turns on.

  A sequence can be entered from somewhere other than its start, and the first
  unpredictable input of it reads as the sequence being lost. So an unexpected
  step is not simply burst: the recent inputs are kept and re-played on the
  assumption that the sequence began further back than the pooler thought. The
  learning pass keeps its own history and does the same thing when it would
  otherwise begin a sequence at the wrong place.
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
  let _inference_inputs: Array[Array[USize] val]
  let _learning_inputs: Array[Array[USize] val]
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
    _inference_inputs = Array[Array[USize] val]
    _learning_inputs = Array[Array[USize] val]
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

  fun active_cells(): Array[USize] val =>
    """
    The cells the inference pass activated at the last step.
    """
    _inference.cells_in_state()

  fun predicted_cells(): Array[USize] val =>
    """
    The cells the inference pass expects at the next step.
    """
    _inference.predicted_cells()

  fun predicted_columns(): Array[USize] val =>
    """
    The nodes the inference pass expects to receive input at the next step.
    """
    let found: Array[USize] iso = recover iso Array[USize] end
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

  fun node_confidences(): Array[F64] val =>
    """
    How much confidence the pooler puts on each node, as shares of the whole.

    The soft counterpart of `predicted_columns` - what the state says, without
    a threshold deciding for the reader. A node nobody's segment reaches is
    zero.
    """
    _confidence.node_confidences()

  fun ref predict(steps: USize): ClaForecast ? =>
    """
    What the pooler expects, step by step, if nothing arrives to correct it.

    The first step is what it already predicts; each one after it is read from the
    state that follows, with the predicted cells taken as the next step's
    activity and no input of its own. The state is put back before this answers,
    so asking what comes next does not decide it.

    Reading several steps ahead like this is worth what the sequences it has
    learned are worth: where the pooler has learned only one continuation the
    second and third steps are the ones it expects, and where it has learned
    several it names all of them rather than choosing.
    """
    if steps == 0 then error end

    let kept = _inference.copy()
    let kept_confidence = _confidence.copy()

    let forecast: Array[Array[F64] val] iso =
      recover iso Array[Array[F64] val] end

    var step: USize = 0
    while step < steps do
      forecast.push(_confidence.node_confidences())

      if (step + 1) < steps then
        _roll_forward()
      end

      step = step + 1
    end

    _inference.restore(kept)
    _confidence.restore(kept_confidence)

    ClaForecast(consume forecast)

  fun ref _roll_forward() =>
    """
    One step with no input: what was predicted becomes what is active, and what
    that makes predicted is the step after it.
    """
    _confidence.advance()
    _inference.advance()
    _inference.activate_predicted()
    _infer_phase2()

  fun ref answer(): ClaOutput =>
    """
    Everything the last step produced, as one value: what it answered with, the
    cells it activated, the cells it predicts, the nodes those belong to, and how
    much confidence each node carries.
    """
    ClaOutput(
      _output(),
      active_cells(),
      predicted_cells(),
      predicted_columns(),
      node_confidences())

  fun ref compute(
    active_columns: ReadSeq[USize],
    learn: Bool,
    infer: Bool): Array[USize] val ?
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
    _inference_inputs.clear()
    _learning_inputs.clear()
    _reset_called = true

  // The inference pass ------------------------------------------------------
  //
  // Inference answers two questions in order: which cells are active, given the
  // input and what was predicted, and which cells does that make predicted next.

  fun ref _update_inference(active_columns: ReadSeq[USize]) =>
    """
    One inference step: what is active given this input, and what that predicts.

    A step whose input was largely unpredicted, or that leaves too little
    predicted for the step after it, has probably lost the sequence - the input
    arrived from somewhere the pooler was not following. Rather than bursting
    and starting over, the recent inputs are re-played on the assumption that
    the sequence began further back than it thought.
    """
    _inference.advance()
    _confidence.advance()
    _remember(active_columns)

    // Where this step began. A re-play writes over the state as it goes, so this
    // is what puts the state back when none of them locks on.
    let started = _inference.copy()
    let started_confidence = _confidence.copy()

    if _infer_phase1(active_columns, _reset_called) and _infer_phase2() then
      return
    end

    if _replay_from_an_earlier_start(started, started_confidence) then return end

    // Nothing locked on: burst on this input as if nothing had been predicted
    // for it, and predict from there.
    _inference.restore(started)
    _confidence.restore(started_confidence)
    _infer_phase1(active_columns, _reset_called)
    _infer_phase2()

  fun ref _remember(active_columns: ReadSeq[USize]) =>
    """
    Keep the input, because a step that turns out to be unexpected is judged
    against the steps that led to it.

    One more input than the pooler may start a re-play from, because the input
    that arrived is kept here too.
    """
    if _config.max_inference_backtrack == 0 then return end

    _inference_inputs.push(_as_value(active_columns))
    while _inference_inputs.size() > (_config.max_inference_backtrack + 1) do
      try _inference_inputs.shift()? end
    end

  fun _as_value(active_columns: ReadSeq[USize]): Array[USize] val =>
    """
    A copy of the input as a value, because the history outlives the step that
    handed it in.
    """
    let kept: Array[USize] iso = recover iso Array[USize] end
    for column in active_columns.values() do
      kept.push(column)
    end
    kept

  fun ref _replay_from_an_earlier_start(
    started: CellState,
    started_confidence: CellConfidence): Bool
  =>
    """
    Assume the sequence started at each of the recent inputs in turn, farthest
    back first, and keep the first start that stays on a sequence all the way to
    the input that arrived.

    Farthest back first because context is what a prediction is made of: if
    starting four steps ago explains this input, that start knows more about what
    comes after it than a start one step ago does. The last start tried is this
    input itself, which is the sequence beginning here.

    Leaves the state alone when nothing locks on, so the caller can carry on with
    what its own phases produced.
    """
    if _config.max_inference_backtrack == 0 then return false end

    var start: USize = 0
    while start < _inference_inputs.size() do
      if _replay(start, started, started_confidence) then
        _forget_before(start)
        return true
      end
      start = start + 1
    end

    false

  fun ref _replay(
    start: USize,
    started: CellState,
    started_confidence: CellConfidence): Bool
  =>
    """
    Play the kept inputs from `start` onwards, the first of them on its start
    cells, and answer whether the pooler stays on a sequence throughout.

    Leaves behind the state the last input produced, which is the state the
    caller wanted when this answers true. When it answers false the state is
    whatever the attempt got to, and the caller has to put its own back.
    """
    _inference.restore(started)
    _confidence.restore(started_confidence)

    for (offset, input) in _inference_inputs.pairs() do
      if offset < start then continue end

      // the step before's prediction is what a step is read against, and the
      // first re-played input is read against start cells instead
      if offset > start then
        _inference.advance()
        _confidence.advance()
      end

      if not (_infer_phase1(input, offset == start) and _infer_phase2()) then
        return false
      end
    end

    true

  fun ref _forget_before(start: USize) =>
    """
    Drop the inputs there is nothing left to learn from: the ones before the
    start the re-play locked on, which it proved were not part of this sequence,
    and that start itself, which is now behind the pooler rather than a place to
    begin from.
    """
    var dropped: USize = 0
    while dropped < start do
      try _inference_inputs.shift()? end
      dropped = dropped + 1
    end

  fun ref _infer_phase1(
    active_columns: ReadSeq[USize],
    from_start_cells: Bool): Bool
  =>
    """
    Decide the active cells: the predicted ones where there are any, the whole
    node where there are none. Told to, or after a reset, nothing is predicted
    into the step and every node starts on its start cell.
    """
    _inference.clear_active()

    if from_start_cells then
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

  fun ref _infer_phase2(): Bool =>
    """
    Decide the prediction, and how sure the pooler is of each part of it.

    Every segment that reaches enough of the active state contributes its own
    record of how often it has been right, whether or not it is strong enough to
    predict: a weak match is still evidence.

    Answers whether the pooler is predicting enough going forward, which is half
    the input density it has been seeing. Below that, what comes next is mostly a
    guess, and this is one of the steps the re-play looks at again.
    """
    _inference.clear_predicted()
    _confidence.clear()

    _gather(_inference.active_bits())
    _confidence.share_out()

    _enough_predicted()

  fun ref _gather(state: ReadSeq[Bool]) =>
    """
    Every segment that reaches enough of the state contributes its own record of
    how often it has been right, and predicts if it is strong enough.
    """
    for node in _nodes.values() do
      for cell in node.cells().values() do
        _gather_from(_config.cell_of(node.index, cell.offset), cell.segments, state)
      end
    end

  fun ref _gather_from(
    name: USize,
    reaching: Array[ClaSegment],
    state: ReadSeq[Bool])
  =>
    for segment in reaching.values() do
      if segment.activity(state) < _config.activation_threshold then continue end

      _confidence.credit(name, segment.duty_cycle(_learning_iteration, false))

      if segment.active(
        state, _config.activation_threshold, _config.connected_threshold)
      then
        _inference.predict(name)
      end
    end

  fun _enough_predicted(): Bool =>
    """
    Whether the pooler is predicting enough going forward: half the input
    density it has been seeing. Below that, what comes next is mostly a guess,
    and this is one of the steps the re-play looks at again.

    Cells are what is counted and columns are what it is counted against, as in
    the reference: a column can contribute more than one predicted cell.
    """
    match _input_density
    | let density: F64 =>
      _inference.count_predicted().f64() >= (0.5 * density)
    else
      true
    end

  // The learning pass -------------------------------------------------------

  fun ref _update_learning(active_columns: ReadSeq[USize]) =>
    """
    One learning step: judge the predictions queued last time, activate this
    step's cells, decide whether the sequence held, and predict ahead.
    """
    _learning.advance()
    _remember_learning(active_columns)
    _process_updates(active_columns)

    if _pam_counter > 0 then _pam_counter = _pam_counter - 1 end
    _learned_sequence_length = _learned_sequence_length + 1

    if not _reset_called then
      if _learn_phase1(active_columns, false) then
        _pam_counter = _config.pam_length
      end
    end

    if _starts_over() then
      _begin_again(active_columns)
    end

    _learn_phase2(false)

  fun _starts_over(): Bool =>
    """
    Whether the learning pass has to begin a sequence: a reset, a sequence that
    has been out of step for longer than the PAM length allows, or the longest
    sequence worth naming.
    """
    _reset_called
      or (_pam_counter == 0)
      or ((_config.max_sequence_length != 0)
        and (_learned_sequence_length >= _config.max_sequence_length))

  fun ref _begin_again(active_columns: ReadSeq[USize]) =>
    """
    Begin a sequence: here on start cells, or further back where the sequence
    these inputs are part of began.

    Beginning here throws away the step before this one, so a sequence that is
    learned in pieces never joins up - the piece ending at the seam is never
    re-enforced against the piece beginning after it. The re-play is what joins
    them: it finds where this sequence began, walks that path again teaching it,
    and says how far back it locked on.
    """
    let steps_back =
      if _reset_called then 0 else _backtrack_learning() end

    if steps_back == 0 then
      _start_over(active_columns)
      return
    end

    _pam_counter = _config.pam_length
    _learned_sequence_length = steps_back
    _updates = Array[ClaSegmentUpdate]

  fun ref _remember_learning(active_columns: ReadSeq[USize]) =>
    """
    Keep the input, because a sequence that has to begin again is judged against
    the inputs that led to it.

    One more input than the pass may start a re-play from, because the input
    that arrived is kept here too.
    """
    if _config.max_learning_backtrack == 0 then return end

    _learning_inputs.push(_as_value(active_columns))
    while _learning_inputs.size() > (_config.max_learning_backtrack + 1) do
      try _learning_inputs.shift()? end
    end

  fun ref _backtrack_learning(): USize =>
    """
    Find where the sequence the recent inputs are part of began, and walk it
    again teaching it.

    The input that arrived is not a start worth trying: this is about where the
    sequence began, not about this step. Answers how many steps back the pass
    locked on, or nothing at all when no earlier input leads here - in which case
    the history goes, because none of it is worth trying again.
    """
    // the input that arrived is the last one, and is not a place to begin from
    if _learning_inputs.size() < 2 then return 0 end

    let explorable = _learning_inputs.size() - 1

    var start: USize = 0
    while start < explorable do
      if _learned_backtrack_from(start, true) then break end
      start = start + 1
    end

    if start == explorable then
      _learning_inputs.clear()
      return 0
    end

    // the same path again, this time teaching it
    _learned_backtrack_from(start, false)
    _forget_learned_before(start)

    explorable - start

  fun ref _learned_backtrack_from(start: USize, read_only: Bool): Bool =>
    """
    Re-play the kept inputs from `start` with the first of them on its start
    cells, and answer whether the sequence holds all the way to the input that
    arrived.

    The input that arrived is re-played too - it is the one that has to be
    explained - but what follows it is not: a prediction for the next step is the
    caller's to make, from the state this leaves behind.

    Read only, nothing is taught and nothing is queued, which is what makes the
    attempt cheap enough to make several times. Not read only, the path is
    re-enforced as it is walked - that is what finding it is for.
    """
    if not read_only then _updates = Array[ClaSegmentUpdate] end

    var in_sequence = true

    for (offset, input) in _learning_inputs.pairs() do
      if offset < start then continue end

      _learning.advance()
      if not read_only then _process_updates(input) end

      if offset == start then
        _start_on_start_cells(input)
      else
        in_sequence = _learn_phase1(input, read_only)
      end

      if not in_sequence then break end

      // what follows the input that arrived is the caller's phase two
      if offset == (_learning_inputs.size() - 1) then break end

      _learn_phase2(read_only)
    end

    in_sequence

  fun ref _forget_learned_before(start: USize) =>
    """
    Drop the inputs before the start the re-play locked on, which it proved the
    sequence does not begin at.
    """
    var dropped: USize = 0
    while dropped < start do
      try _learning_inputs.shift()? end
      dropped = dropped + 1
    end

  fun ref _learn_phase1(active_columns: ReadSeq[USize], read_only: Bool): Bool =>
    """
    Activate the predicted cell of every node that received input, and teach the
    nodes that were not predicted.

    Read only, from a re-play, nothing is taught, and a node with no prediction
    keeps no active cell at all: the re-play is asking whether the sequence
    holds, not changing what is known.

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
      if read_only then continue end

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

  fun ref _learn_phase2(read_only: Bool) =>
    """
    Predict ahead, and queue what each prediction would change.

    At most one cell of a node is predicted in the learning pass: the one whose
    best segment matches the active state. The proposal is queued rather than
    applied because whether it was right is only known when the next input
    arrives. Read only, the prediction is made and nothing is queued.
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

        if not read_only then
          segment.total = segment.total + 1

          let reach_more = found.activity < _config.new_synapse_count
          let update = _synapses_for(column, found.offset, segment, state, reach_more)
          if update.proposed() then _updates.push(update) end

          if _config.pooling then
            _queue_pooling(column, found.offset, before)
          end
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
    Begin a sequence here rather than further back, which is what a reset asks
    for and what a pass that can find no earlier beginning falls back on.
    """
    _start_on_start_cells(active_columns)
    _pam_counter = _config.pam_length
    _learned_sequence_length = 0
    _updates = Array[ClaSegmentUpdate]

  fun ref _start_on_start_cells(active_columns: ReadSeq[USize]) =>
    """
    Put every node that received input on its start cell, which is what a
    sequence beginning here looks like.
    """
    _learning.clear_active()

    for column in active_columns.values() do
      _learning.activate(_config.cell_of(column, 0))
    end

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
    if wanted == 0 then return Array[USize] end

    let candidates = _reachable(segment, state)
    if candidates.size() <= wanted then return candidates end

    if wanted == 1 then return _one_of(candidates) end
    _some_of(candidates, wanted)

  fun _reachable(
    segment: (ClaSegment | None),
    state: ReadSeq[Bool]): Array[USize]
  =>
    """
    The cells that are active now and that this segment does not already reach.
    """
    let candidates = Array[USize]

    var cell: USize = 0
    while cell < state.size() do
      try
        if state(cell)? and not _reaches_nothing(segment, cell) then
          candidates.push(cell)
        end
      end
      cell = cell + 1
    end

    candidates

  fun _reaches_nothing(segment: (ClaSegment | None), cell: USize): Bool =>
    match segment
    | let existing: ClaSegment => existing.reaches(cell)
    | None => false
    end

  fun ref _one_of(candidates: Array[USize]): Array[USize] =>
    let picked = Array[USize]
    try picked.push(candidates(_rand.int(candidates.size()))?) end
    picked

  fun ref _some_of(candidates: Array[USize], wanted: USize): Array[USize] =>
    """
    A random subset of the candidates, without replacement.

    An inside-out shuffle: each candidate is swapped with one already placed, so
    every permutation is equally likely and nothing beyond `wanted` is touched.
    """
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

  fun ref _output(): Array[USize] val =>
    """
    What the step answers with: every cell that is active or predicted.
    """
    let out: Array[USize] iso = recover iso Array[USize] end

    for node in _nodes.values() do
      for cell in node.cells().values() do
        let name = _config.cell_of(node.index, cell.offset)
        if _inference.active(name) or _inference.predicted(name) then
          out.push(name)
        end
      end
    end

    out
