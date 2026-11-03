use "collections"
use "random"

primitive SDRMerger
  """
  Putting two sparse representations together, and cutting one down to size.

  Everything in this library that composes fields has done it by hand: the date
  encoder adds offsets to each field as it writes it, and the document encoder
  votes over one whole vector. Neither can express "this context, then that
  content" as one representation - the concatenation of two spaces - which is
  what a pooler needs when it is given a pattern *and* the situation the pattern
  is in.

  Two operations, not three. Concatenation and subsampling are the two a caller
  has asked for; the reference's third mode, distorting a representation, has no
  caller here and an unclear account of what it should do, so it is not guessed
  at.
  """

  fun concat(
    left: ReadSeq[USize],
    right: ReadSeq[USize],
    shift: USize): Array[USize] val
  =>
    """
    One representation from two, with the right-hand one moved to `shift`.

    The two are different spaces - a context encoding and a content encoding -
    and `shift` is where the second begins, which is the first one's width. The
    answer is ascending and holds each position once, because a representation is
    a set: a caller whose spaces overlap gets the overlap merged rather than
    counted twice.
    """
    let merged = Set[USize]

    for index in left.values() do
      merged.set(index)
    end

    for index in right.values() do
      merged.set(shift + index)
    end

    _ordered(merged)

  fun subsample(
    indices: ReadSeq[USize],
    most: USize,
    seed: U64 = 42): Array[USize] val
  =>
    """
    At most `most` of the given positions, chosen without replacement.

    A representation that keeps growing stops being sparse, and a pooler is
    tuned for a density. Given the seed the answer is the same every time, which
    is what makes a subsampled encoding something a test can state.

    Fewer positions than asked for are all kept: there is nothing to leave out.
    """
    let unique = Set[USize]
    for index in indices.values() do
      unique.set(index)
    end

    let all = _ordered(unique)
    if all.size() <= most then return all end

    let shuffled = _shuffled(all, seed)
    _first(shuffled, most)

  fun _shuffled(all: ReadSeq[USize], seed: U64): Array[USize] ref =>
    """
    The positions in a random order, drawn from a warmed-up generator.

    Pony's generator is weak over the first few draws after seeding, which would
    make the choice follow the seed rather than chance, so it is warmed up first.
    The shuffle itself is inside-out: every position is swapped with one of the
    positions up to it.
    """
    let candidates: Array[USize] ref = Array[USize]
    for index in all.values() do
      candidates.push(index)
    end

    let random = Rand(seed)
    var warming: USize = 0
    while warming < 16 do
      random.next()
      warming = warming + 1
    end

    var placed: USize = 0
    while placed < candidates.size() do
      let other = random.int(placed + 1)
      try
        let held = candidates(placed)?
        candidates(placed)? = candidates(other)?
        candidates(other)? = held
      end
      placed = placed + 1
    end

    candidates

  fun _first(candidates: ReadSeq[USize], most: USize): Array[USize] val =>
    """
    The first `most` of them, put back in ascending order.
    """
    let kept = Set[USize]
    var taken: USize = 0
    while taken < most do
      try kept.set(candidates(taken)?) end
      taken = taken + 1
    end

    _ordered(kept)

  fun _ordered(from: Set[USize]): Array[USize] val =>
    """
    The set's positions in ascending order, which is how a representation is
    written down everywhere else here.

    Sorted by selection rather than through the standard library's sort, because
    the result has to leave as an immutable array and the sort wants it mutable:
    these sets are small, and this borrows nothing.
    """
    let sorted: Array[USize] iso = recover iso Array[USize] end

    for index in from.values() do
      sorted.push(index)
    end

    let count = sorted.size()
    var start: USize = 0
    while start < count do
      var smallest = start
      var scan = start + 1
      while scan < count do
        try
          if sorted(scan)? < sorted(smallest)? then smallest = scan end
        end
        scan = scan + 1
      end

      try
        let held = sorted(start)?
        sorted(start)? = sorted(smallest)?
        sorted(smallest)? = held
      end

      start = start + 1
    end

    consume sorted
