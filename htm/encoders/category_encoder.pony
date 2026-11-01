class val CategoryEncoder
  """
  Encodes categories that have no order between them.

  Each category owns `bits` consecutive positions of the output and no two
  categories share one, so two different categories have nothing in common -
  which is what "no order between them" means in a representation. Unlike the
  [scalar encoder](scalar_encoder.md), neighbouring categories do not slide
  into each other: there is nothing between two categories to be between.

  The output is as wide as the categories need, `bits * categories`, so a
  population that grows with the number of labels is the price of not knowing
  them in advance.

  nupic's category encoder keeps the first block for `<UNKNOWN>` and encodes
  anything it has not seen there. This one refuses instead: a stream where
  unseen labels quietly become a real block is a stream whose labels stopped
  being checked. The difference is deliberate and is the only one.
  """
  let categories: Array[String] val
  let bits: USize

  new val create(categories': Array[String] val, bits': USize = 3) ? =>
    """
    `bits` is how many positions a category owns. One is enough to tell
    categories apart; more of them survive the pooling better, which is the same
    reason the scalar encoder sets several bits per value.
    """
    if (bits' == 0) or (categories'.size() == 0) then error end

    var first: USize = 0
    while first < categories'.size() do
      var second: USize = first + 1
      while second < categories'.size() do
        if categories'(first)? == categories'(second)? then error end
        second = second + 1
      end
      first = first + 1
    end

    categories = categories'
    bits = bits'

  fun width(): USize => bits * categories.size()

  fun index_of(category: String): (USize | None) =>
    var index: USize = 0
    for known in categories.values() do
      if known == category then return index end
      index = index + 1
    end
    None

  fun encode(category: String): (Array[Bool] | EncodingFailed) =>
    match index_of(category)
    | let index: USize =>
      let encoded: Array[Bool] iso =
        recover iso Array[Bool].init(false, width()) end

      var offset: USize = 0
      while offset < bits do
        try encoded((index * bits) + offset)? = true end
        offset = offset + 1
      end

      consume encoded
    else
      EncodingFailed
    end

  fun decode(encoded: ReadSeq[Bool]): (String | EncodingFailed) =>
    """
    The category whose block is the busiest in this encoding.

    A category is read back from a representation that has been through a
    pooler, so the block will not be intact; counting is what survives.
    """
    var best: USize = 0
    var busiest: USize = 0

    var index: USize = 0
    while index < categories.size() do
      let active = _active_in(encoded, index * bits)
      if active > busiest then
        busiest = active
        best = index
      end
      index = index + 1
    end

    if busiest == 0 then return EncodingFailed end

    try categories(best)? else EncodingFailed end

  fun _active_in(encoded: ReadSeq[Bool], start: USize): USize =>
    var active: USize = 0
    var offset: USize = 0
    while offset < bits do
      let position = start + offset
      if position >= encoded.size() then return active end
      try
        if encoded(position)? then active = active + 1 end
      end
      offset = offset + 1
    end
    active
