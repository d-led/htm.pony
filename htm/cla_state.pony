class CellState
  """
  Which cells are in a state, and which were before.

  The pooler runs two of these side by side. One belongs to the learning pass,
  where a state is what the pooler *thinks*; the other belongs to the inference
  pass, where a state is what it can *show*, and which is also the one the
  confidences are kept for. Both answer the same three questions: is this cell in
  the state now, was it in it at the step before, and which cells of a node are in
  it.
  """
  let columns: USize
  let cells_per_column: USize
  var _active: Array[Bool]
  var _active_before: Array[Bool]
  var _predicted: Array[Bool]
  var _predicted_before: Array[Bool]

  new create(columns': USize, cells_per_column': USize) =>
    columns = columns'
    cells_per_column = cells_per_column'
    let cells = columns' * cells_per_column'
    _active = Array[Bool].init(false, cells)
    _active_before = Array[Bool].init(false, cells)
    _predicted = Array[Bool].init(false, cells)
    _predicted_before = Array[Bool].init(false, cells)

  fun ref advance() =>
    """
    Everything that is true now becomes true at the step before, which is what
    the next step's learning and prediction are read against.
    """
    _active_before = _active.clone()
    _predicted_before = _predicted.clone()

  fun ref clear_active() =>
    """
    Start a fresh active state. The pass that computes one fills it in.
    """
    _active = Array[Bool].init(false, _active.size())

  fun ref clear_predicted() =>
    """
    Start a fresh prediction. The pass that computes one fills it in.
    """
    _predicted = Array[Bool].init(false, _predicted.size())

  fun ref clear_before() =>
    """
    Forget what the step before looked like, which is what a reset does: after it
    the next step is not a continuation of anything.
    """
    _active_before = Array[Bool].init(false, _active_before.size())
    _predicted_before = Array[Bool].init(false, _predicted_before.size())

  fun ref activate(cell: USize) =>
    """
    Turn a cell's active state on. A cell outside the population is ignored
    rather than raised on: an actor cannot refuse a message and this library
    keeps that rule everywhere.
    """
    try _active(cell)? = true end

  fun ref predict(cell: USize) =>
    """
    Turn a cell's predicted state on.
    """
    try _predicted(cell)? = true end

  fun active(cell: USize): Bool =>
    """
    Whether this cell is active now.
    """
    try _active(cell)? else false end

  fun predicted(cell: USize): Bool =>
    """
    Whether this cell is predicted now.
    """
    try _predicted(cell)? else false end

  fun was_active(cell: USize): Bool =>
    """
    Whether this cell was active at the step before.
    """
    try _active_before(cell)? else false end

  fun was_predicted(cell: USize): Bool =>
    """
    Whether this cell was predicted at the step before.
    """
    try _predicted_before(cell)? else false end

  fun active_in(node: USize): Array[USize] val =>
    """
    The cells of one node that are active now.
    """
    _in(_active, node)

  fun active_in_before(node: USize): Array[USize] val =>
    """
    The cells of one node that were active at the step before.
    """
    _in(_active_before, node)

  fun predicted_in_before(node: USize): Array[USize] val =>
    """
    The cells of one node that were predicted at the step before, which is what
    the current step's activity is decided against.
    """
    _in(_predicted_before, node)

  fun cells_in_state(): Array[USize] val =>
    """
    Every cell that is active now, by its name in the whole population.
    """
    _all(_active)

  fun predicted_cells(): Array[USize] val =>
    """
    Every cell that is predicted now.
    """
    _all(_predicted)

  fun ref active_bits(): Array[Bool] ref^ =>
    """
    The active cells as a flat vector, as a copy.

    A copy and not a view: a pass reads the state through this while it is
    setting the predictions that follow from it, and reading through an alias of
    the thing being written is exactly what a borrowed reference forbids.
    """
    _active.clone()

  fun ref active_bits_before(): Array[Bool] ref^ =>
    """
    The cells that were active at the step before, as a flat vector.
    """
    _active_before.clone()

  fun predicted_in(node: USize): Array[USize] val =>
    """
    The cells of one node that are predicted now. In the learning pass there is
    at most one: the best matching segment of the node settles it.
    """
    _in(_predicted, node)

  fun count_active(): USize =>
    """
    How many cells are active now.
    """
    _count(_active)

  fun count_predicted(): USize =>
    """
    How many cells are predicted now.
    """
    _count(_predicted)

  fun ref activate_predicted() =>
    """
    Make what was predicted the activity, which is what a step with no input of
    its own does: the pooler carries on from what it expected.
    """
    _active = _predicted.clone()

  fun ref restore(snapshot: CellState) =>
    """
    Take a snapshot's contents back, which is what a re-played step needs: the
    state is put back where it was, rather than a new state taking its place,
    because everything that holds it holds this one.
    """
    _active = snapshot._active.clone()
    _active_before = snapshot._active_before.clone()
    _predicted = snapshot._predicted.clone()
    _predicted_before = snapshot._predicted_before.clone()

  fun ref copy(): CellState =>
    """
    A copy to carry a step into the future and back again, which is what a
    prediction several steps out needs.
    """
    let carried = CellState(columns, cells_per_column)
    carried._active = _active.clone()
    carried._active_before = _active_before.clone()
    carried._predicted = _predicted.clone()
    carried._predicted_before = _predicted_before.clone()
    carried

  fun _in(states: ReadSeq[Bool], node: USize): Array[USize] val =>
    let found: Array[USize] iso = recover iso Array[USize] end
    let start = node * cells_per_column
    var offset: USize = 0
    while offset < cells_per_column do
      try
        if states(start + offset)? then found.push(offset) end
      end
      offset = offset + 1
    end
    found

  fun _all(states: ReadSeq[Bool]): Array[USize] val =>
    let found: Array[USize] iso = recover iso Array[USize] end
    var cell: USize = 0
    while cell < states.size() do
      try
        if states(cell)? then found.push(cell) end
      end
      cell = cell + 1
    end
    found

  fun _count(states: ReadSeq[Bool]): USize =>
    var counted: USize = 0
    for state in states.values() do
      if state then counted = counted + 1 end
    end
    counted

class CellConfidence
  """
  How much of the pooler's confidence sits on each cell, and on the node that
  owns it.

  A cell earns confidence from every segment that matches well, whether or not
  the segment is strong enough to predict - a weak match is still evidence - and
  its node's confidence is the sum of its cells'. The whole set is divided by its
  own total before it is shown, so a column answers "how sure, relative to
  everything I am sure about", which is what a reader of a chart wants and what
  the reference does.
  """
  let cells_per_column: USize
  var _cells: Array[F64]
  var _cells_before: Array[F64]
  var _nodes: Array[F64]
  var _nodes_before: Array[F64]

  new create(columns: USize, cells_per_column': USize) =>
    cells_per_column = cells_per_column'
    _cells = Array[F64].init(0.0, columns * cells_per_column')
    _cells_before = Array[F64].init(0.0, columns * cells_per_column')
    _nodes = Array[F64].init(0.0, columns)
    _nodes_before = Array[F64].init(0.0, columns)

  fun ref advance() =>
    """
    Keep the confidences of this step as the step before's.
    """
    _cells_before = _cells.clone()
    _nodes_before = _nodes.clone()

  fun ref clear() =>
    """
    Start a fresh set. The pass that computes one fills it in.
    """
    _cells = Array[F64].init(0.0, _cells.size())
    _nodes = Array[F64].init(0.0, _nodes.size())

  fun ref clear_before() =>
    """
    Forget the confidences of the step before, which is what a reset does.
    """
    _cells_before = Array[F64].init(0.0, _cells_before.size())
    _nodes_before = Array[F64].init(0.0, _nodes_before.size())

  fun ref credit(cell: USize, amount: F64) =>
    """
    Give a cell and its node some confidence.
    """
    try
      _cells(cell)? = _cells(cell)? + amount
      _nodes(cell / cells_per_column)? = _nodes(cell / cells_per_column)? + amount
    end

  fun cell_confidence(cell: USize): F64 =>
    """
    What one cell is worth.
    """
    try _cells(cell)? else 0.0 end

  fun cell_confidence_before(cell: USize): F64 =>
    """
    What one cell was worth at the step before.
    """
    try _cells_before(cell)? else 0.0 end

  fun node_confidence(node: USize): F64 =>
    """
    What one node is worth.
    """
    try _nodes(node)? else 0.0 end

  fun total(): F64 =>
    """
    The confidence there is, added up over the nodes.
    """
    var summed: F64 = 0.0
    for value in _nodes.values() do
      summed = summed + value
    end
    summed

  fun ref share_out() =>
    """
    Turn the raw credits into shares of the whole.

    Nothing to share out leaves the set as it is, and that matters: an all-zero
    set divided by zero is every cell equally confident and equally meaningless.
    """
    let summed = total()
    if summed <= 0.0 then return end

    var node: USize = 0
    while node < _nodes.size() do
      try
        _nodes(node)? = _nodes(node)? / summed
      end
      node = node + 1
    end

    var cell: USize = 0
    while cell < _cells.size() do
      try
        _cells(cell)? = _cells(cell)? / summed
      end
      cell = cell + 1
    end

  fun node_confidences(): Array[F64] val =>
    """
    What every node is worth, in node order, as a copy.
    """
    let shares: Array[F64] iso = recover iso Array[F64] end
    for value in _nodes.values() do
      shares.push(value)
    end
    shares

  fun ref restore(snapshot: CellConfidence) =>
    """
    Take a snapshot's confidences back.
    """
    _cells = snapshot._cells.clone()
    _cells_before = snapshot._cells_before.clone()
    _nodes = snapshot._nodes.clone()
    _nodes_before = snapshot._nodes_before.clone()

  fun ref copy(): CellConfidence =>
    """
    A copy to carry a step into the future and back again.
    """
    let carried = CellConfidence(_nodes.size(), cells_per_column)
    carried._cells = _cells.clone()
    carried._cells_before = _cells_before.clone()
    carried._nodes = _nodes.clone()
    carried._nodes_before = _nodes_before.clone()
    carried
