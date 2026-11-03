class val ClaForecast
  """
  What a pooler expects several steps ahead, if nothing arrives to correct it.

  One array of nodes per step: step one is what the pooler already expects next,
  and each one after that is read from the state that follows, with the predicted
  cells taken as the next step's activity and no input of its own.

  The confidences are kept as well, because a forecast that only named nodes
  could not say how much of a guess each of them is. Each is a share of the whole
  at that step, so a step whose nodes are all equally likely has every one of
  them small - which is what makes a forecast several steps out worth reading
  rather than trusting.
  """
  let _confidences: Array[Array[F64] val] val

  new val create(confidences': Array[Array[F64] val] val) =>
    _confidences = confidences'

  fun size(): USize =>
    """
    How many steps ahead the forecast reaches.
    """
    _confidences.size()

  fun nodes(step: USize): Array[USize] val ? =>
    """
    The nodes the pooler puts any confidence on at that step, in node order.
    """
    let found: Array[USize] iso = recover iso Array[USize] end
    for (node, confidence) in confidences(step)?.pairs() do
      if confidence > 0.0 then found.push(node) end
    end
    found

  fun confidences(step: USize): Array[F64] val ? =>
    """
    The confidence on every node at that step, which is what `nodes` reads.
    """
    _confidences(step)?
