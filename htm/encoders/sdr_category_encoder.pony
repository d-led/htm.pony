use "collections"
use "random"

class SDRCategoryEncoder
  """
  Encodes categories whose number is not known in advance.

  Fixed width: every encoding is the same size however many labels have been met,
  and each category turns on `bits` of that width, chosen at random. Two
  categories may therefore share a position, which a closed-set encoder would
  never allow - the trade is that a label arriving later needs no room, because
  it is given bits out of the same fixed width as it is met.

  `CategoryEncoder` beside it is the other shape: contiguous blocks, a width that
  grows with the labels, and an unseen label refused. This one is for a stream of
  labels that keeps producing new ones, and for a pooler whose input width cannot
  move.

  An encoding from this encoder and one from `CategoryEncoder` are not
  comparable: they do not even agree on whether two categories may share a bit.
  """

  let size: USize
  let bits: USize
  let _labels: Map[String, Array[USize] val]
  let _random: Rand
  let _unknown: Array[USize] val

  new create(size': USize, bits': USize = 0, seed: U64 = 42) ? =>
    """
    A width of `size'` positions and `bits'` of them on per category. Zero for
    `bits'` means two percent of the width, at least one - the density
    `htm.core`'s category encoder defaults to.

    Fails when there is no width to encode into, or when more bits are asked for
    than the width has.
    """
    if size' == 0 then error end

    let chosen =
      if bits' == 0 then
        let share = size' / 50
        if share == 0 then 1 else share end
      else
        bits'
      end

    if (chosen == 0) or (chosen > size') then error end

    size = size'
    bits = chosen
    _labels = Map[String, Array[USize] val]

    // Pony's generator is weak for the first few draws after seeding: it tracks
    // the seed closely enough that a small draw would be decided by the seed
    // rather than by chance.
    let random = Rand(seed)
    var warming: USize = 0
    while warming < 16 do
      random.next()
      warming = warming + 1
    end
    _random = random

    _unknown = RandomPositions.pick(size', chosen, random)

  fun width(): USize =>
    """
    How wide every encoding is, whatever has been met.
    """
    size

  fun bits_on(): USize =>
    """
    How many positions a category turns on.
    """
    bits

  fun labels(): USize =>
    """
    How many categories have been met.
    """
    _labels.size()

  fun knows(label: String): Bool =>
    """
    Whether this label has been met before.
    """
    _labels.contains(label)

  fun unknown(): Array[USize] val =>
    """
    The positions that stand for a label nobody has given.

    It is there from the start, before any label is met, so a caller always has
    something to encode when the answer is "I do not know".
    """
    _unknown

  fun ref encode(label: String): Array[USize] val =>
    """
    The positions for a label, giving it new ones the first time it is seen.

    This is why the set is open: a label nobody has met is encoded, not refused,
    and it keeps the same positions from then on.
    """
    try
      _labels(label)?
    else
      let picked = RandomPositions.pick(size, bits, _random)
      _labels(label) = picked
      picked
    end

primitive RandomPositions
  """
  The draw behind the open-set category encoder: `bits` distinct positions of a
  width, chosen at random.

  A primitive rather than a method on the encoder, because a constructor cannot
  call its own methods: `this` is `tag` until every field is assigned, and the
  unknown category is the last of them.
  """
  fun pick(size: USize, bits: USize, random: Rand ref): Array[USize] val =>
    """
    `bits` distinct positions, chosen at random.

    A copy of every position is shuffled and the first `bits` of it are taken,
    which draws without replacement and needs no rejection loop when most of the
    width is wanted. The answer is ascending, like every other representation
    here.
    """
    let positions = _shuffled(size, random)
    let on = _marked(positions, bits, size)
    _ascending(on, size)

  fun _shuffled(size: USize, random: Rand ref): Array[USize] ref =>
    """
    Every position, in an order drawn at random.
    """
    let positions: Array[USize] ref = Array[USize]
    var index: USize = 0
    while index < size do
      positions.push(index)
      index = index + 1
    end

    var placed: USize = 0
    while placed < size do
      let other = random.int(placed + 1)
      try
        let held = positions(placed)?
        positions(placed)? = positions(other)?
        positions(other)? = held
      end
      placed = placed + 1
    end

    positions

  fun _marked(positions: ReadSeq[USize], bits: USize, size: USize): Array[Bool] =>
    """
    The first `bits` of the shuffled positions, as a flag per position.
    """
    let on = Array[Bool].init(false, size)

    var taken: USize = 0
    while taken < bits do
      try on(positions(taken)?)? = true end
      taken = taken + 1
    end

    on

  fun _ascending(on: ReadSeq[Bool], size: USize): Array[USize] val =>
    """
    The flagged positions, in order.
    """
    let chosen: Array[USize] iso = recover iso Array[USize] end

    var position: USize = 0
    while position < size do
      try
        if on(position)? then chosen.push(position) end
      end
      position = position + 1
    end

    consume chosen
