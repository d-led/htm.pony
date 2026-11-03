primitive Retrieval
  """
  Does a representation put pictures of one thing before pictures of another,
  counted rather than eyeballed?

  Everything here reads distances and labels rather than pictures, so the same
  arithmetic answers the question for a fingerprint, for a representation, and
  for a set of columns: one query is a list of `(distance, label)` pairs, one
  for every other picture of the corpus.
  """

  fun obstacles(
    candidates: ReadSeq[(USize, String val)],
    own: String val)
    : USize
  =>
    """
    How many pictures of another class come closer than the nearest picture of
    the query's own class.

    Nought means the nearest neighbour is a classmate, which is what top-1
    retrieval asks. A few means the representation does put the class first,
    just not immediately. As many as there are other pictures means no picture
    of the class was found at all.

    A distance counts only when it is strictly smaller, so a picture that ties
    with the nearest classmate is not counted against it: on a sixty-four bit
    fingerprint ties are common, and this is what keeps the number stable.
    """
    let nearest: USize = _nearest_own(candidates, own)
    var before: USize = 0
    for (distance, label) in candidates.values() do
      if (label != own) and (distance < nearest) then
        before = before + 1
      end
    end
    before

  fun _nearest_own(
    candidates: ReadSeq[(USize, String val)],
    own: String val)
    : USize
  =>
    var nearest: USize = USize.max_value()
    for (distance, label) in candidates.values() do
      if (label == own) and (distance < nearest) then nearest = distance end
    end
    nearest

  fun mean_distance(
    candidates: ReadSeq[(USize, String val)],
    own: String val,
    same_class: Bool)
    : F64
  =>
    """
    The mean distance to the pictures of the query's own class, or to the
    pictures of every other class.

    Two means that sit far apart say the representation separates the classes;
    two means that overlap say it does not, whatever top-1 happens to be on one
    corpus.
    """
    let distances: Array[F64] = Array[F64]
    for (distance, label) in candidates.values() do
      if (label == own) == same_class then
        distances.push(distance.f64())
      end
    end
    mean(distances)

  fun mean(values: ReadSeq[F64]): F64 =>
    """
    The arithmetic mean, and nought for no values rather than a division by it.
    """
    if values.size() == 0 then return 0.0 end
    var total: F64 = 0.0
    for value in values.values() do
      total = total + value
    end
    total / values.size().f64()
