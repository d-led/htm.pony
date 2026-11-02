class ClaCellMatch
  """
  What a node answers when it is asked which of its cells fits a state best.

  `offset` is the cell, `segment` the segment that made it the answer - nothing
  at all when no segment of the node reaches the threshold - and `activity` how
  much of the state that segment reaches.
  """
  let offset: USize
  let segment: (ClaSegment | None)
  let activity: USize

  new create(offset': USize, segment': (ClaSegment | None), activity': USize) =>
    offset = offset'
    segment = segment'
    activity = activity'

class ClaCell
  """
  One cell of one node: the segments it has grown, and how to ask them together.

  A cell is where a sequence is remembered. One segment on it says "this is what
  came before me", and a second segment on the same cell says "or that did" - so
  a cell that fires can belong to more than one path through the same pattern,
  which is what a column of several cells buys over a single unit.
  """
  let node: USize
  let offset: USize
  var segments: Array[ClaSegment]

  new create(node': USize, offset': USize) =>
    node = node'
    offset = offset'
    segments = Array[ClaSegment]

  fun ref new_segment(iteration: U64): ClaSegment =>
    """
    Give this cell one more memory to learn on.
    """
    let segment = ClaSegment(iteration)
    segments.push(segment)
    segment

  fun best_segment(
    state: ReadSeq[Bool],
    min_threshold: USize): (ClaSegment box | None)
  =>
    """
    The segment that matches the state best, if any of them matches well enough
    to be worth learning on.

    The permanences of the synapses are not consulted - only how many of them
    reach active cells - because a segment that is close is exactly the one that
    should be pulled the rest of the way. When two segments see the same
    activity the later one answers, as in the reference.
    """
    var best_activity = min_threshold
    var best: (ClaSegment box | None) = None

    for segment in segments.values() do
      let activity = segment.activity(state)
      if activity >= best_activity then
        best_activity = activity
        best = segment
      end
    end

    best

  fun strongest(state: ReadSeq[Bool]): (USize, USize) =>
    """
    The best match this cell can offer, as `(activity, segment)`: how much of the
    state its best segment reaches, and which segment that is.

    The first segment to reach that much answers - a later one has to beat it,
    not equal it. `best_segment` breaks ties the other way, because the two
    answer different questions: this one asks whether the cell is worth learning
    on at all, that one asks which segment to teach.
    """
    var best_activity: USize = 0
    var which: USize = 0

    for (index, segment) in segments.pairs() do
      let activity = segment.activity(state)
      if activity > best_activity then
        best_activity = activity
        which = index
      end
    end

    (best_activity, which)

  fun ref add(segment: ClaSegment) =>
    """
    Give this cell one more memory.
    """
    segments.push(segment)

  fun ref trim(segment: ClaSegment, min_permanence: F64) =>
    """
    Forget a segment's weakest synapses, and the segment itself when nothing is
    left of it.

    Only the segment that asked is trimmed: going over every segment of every
    cell each step would be the same work for a much smaller effect, since only a
    segment that was just changed can have reached zero.
    """
    segment.drop_weak(min_permanence)
    if segment.synapses.size() > 0 then return end

    try
      let index = segments.find(segment)?
      segments.remove(index, 1)
    end

  fun ref replace(kept: Array[ClaSegment]) =>
    """
    Take the segments a decay pass decided are worth keeping.
    """
    segments = kept

class ClaNode
  """
  One node of the pooler: the cells that share it.

  The node is what receives input. Its cells are the states it can be in when it
  does, and what it has learned is the segments of those cells - so a node that
  fires the same cell twice is in the same state twice, and one that fires
  different cells is telling its neighbourhood that it was in different
  situations.
  """
  let index: USize
  let _cells: Array[ClaCell]

  new create(index': USize, count: USize) =>
    index = index'
    let made = Array[ClaCell](count)
    var offset: USize = 0
    while offset < count do
      made.push(ClaCell(index', offset))
      offset = offset + 1
    end
    _cells = made

  fun ref cells(): Array[ClaCell] =>
    """
    This node's cells, in the order they were made. Handed out to be learned
    on, which is why it is the node's own array and not a copy.
    """
    _cells
