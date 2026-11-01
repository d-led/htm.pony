// https://github.com/htm-community/htm/blob/master/spatialPooler.go : inhibitColumnsGlobal

primitive Inhibition
  """
  Which columns represent the current input.

  A column's overlap only says how much of the input it recognises; inhibition
  is the competition that turns those claims into a representation, keeping the
  strongest and silencing the rest.
  """

  fun winners(overlaps: ReadSeq[F64], count: USize): Array[USize] ? =>
    """
    The `count` strongest columns.

    Returned in ascending column order, so the result does not depend on the
    order the strength happened to be discovered in. A tie goes to the earlier
    column; the pooler adds a small tie-breaker before calling, so real
    competition rarely reaches this rule.
    """
    let strongest = Array[USize]

    var column: USize = 0
    for overlap in overlaps.values() do
      _offer(strongest, overlaps, column, count)?
      column = column + 1
    end

    _ascending(strongest)?

  fun _offer(strongest: Array[USize], overlaps: ReadSeq[F64], candidate: USize, count: USize) ? =>
    """
    Keep `strongest` sorted best-first and never longer than `count`.
    """
    if count == 0 then return end

    let candidate_overlap = overlaps(candidate)?

    var position: USize = 0
    var placed = false
    while position < strongest.size() do
      let other = strongest(position)?
      let other_overlap = overlaps(other)?

      if (candidate_overlap > other_overlap) or
        ((candidate_overlap == other_overlap) and (candidate < other))
      then
        strongest.insert(position, candidate)?
        placed = true
        break
      end

      position = position + 1
    end

    if not placed then
      strongest.push(candidate)
    end

    if strongest.size() > count then
      strongest.pop()?
    end

  fun local(overlaps: ReadSeq[F64], grid: Grid, radius: USize, density: F64): Array[USize] ? =>
    """
    The columns that stand out among their own neighbours.

    A column wins when fewer than the area's allowance of its neighbours beat
    it. Comparisons are local, so two distant regions of the grid can each be
    represented by their own strongest column.
    """
    let active = Array[USize]

    var column: USize = 0
    while column < grid.size do
      let neighbours = grid.neighbours(column, radius, false)?
      let allowance = _allowance(neighbours.size(), density)

      var beaten_by: USize = 0
      for neighbour in neighbours.values() do
        if _outranks(overlaps, neighbour, column)? then
          beaten_by = beaten_by + 1
        end
      end

      if beaten_by < allowance then
        active.push(column)
      end

      column = column + 1
    end

    active

  fun _allowance(neighbour_count: USize, density: F64): USize =>
    """
    How many columns of a neighbourhood may be active. The column itself counts
    towards its own neighbourhood, so a lone column always has room.
    """
    ((density * (neighbour_count + 1).f64()) + 0.5).usize()

  fun _outranks(overlaps: ReadSeq[F64], challenger: USize, other: USize): Bool ? =>
    """
    Whether one column beats another. Equal overlaps are settled by position, so
    that "the strongest in a neighbourhood" always names exactly one column.
    """
    let challenger_overlap = overlaps(challenger)?
    let other_overlap = overlaps(other)?

    if challenger_overlap != other_overlap then
      challenger_overlap > other_overlap
    else
      challenger < other
    end

  fun _ascending(columns: Array[USize]): Array[USize] ? =>
    let sorted = Array[USize](columns.size())
    for column in columns.values() do
      var position: USize = 0
      var placed = false
      while position < sorted.size() do
        if column < sorted(position)? then
          sorted.insert(position, column)?
          placed = true
          break
        end
        position = position + 1
      end
      if not placed then sorted.push(column) end
    end
    sorted
