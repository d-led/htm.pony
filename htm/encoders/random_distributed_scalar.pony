use "collections"
use "random"

class RandomDistributedScalarEncoder
  """
  Encodes a real number into a random-looking set of bits whose overlap carries
  the distance.

  A scalar encoder slides a window of bits along a range, so a value's place in
  the range decides its bits and the range has to be known up front. This one
  does not: it keeps a map from bucket to representation, creates a bucket the
  first time a value falls into it, and gives each new bucket exactly one bit
  different from its neighbour. Adjacent buckets therefore overlap in all but
  one bit, values two buckets apart overlap in all but two, and once the
  distance reaches the width of a representation the overlap has to fall to
  almost nothing.

  The cost is that the encoding depends on the order values arrive in, and that
  a fresh encoder gives different bits from another one unless they share a seed.
  What is stable is the property that matters: near values overlap.

  The rules are nupic's `RandomDistributedScalarEncoder`: a width of `w` bits
  out of `n` positions, a bucket per `resolution`, at most `max_overlap` bits in
  common between representations far enough apart, and a parent bucket for a new
  one always one index away. The bits are not the same bits nupic would pick,
  because they come from this library's generator rather than numpy's.
  """
  let active_bits: USize
  let positions: USize
  let resolution: F64
  let _max_overlap: USize = 2
  let _max_buckets: USize = 1000
  let _random: Rand
  let _buckets: Map[USize, Array[USize] val]

  var _offset: (F64 | None) = None
  var _lowest: USize
  var _highest: USize

  new create(
    resolution': F64,
    active_bits': USize = 21,
    positions': USize = 400,
    seed: U64 = 42) ?
  =>
    """
    A width of `active_bits` set in `positions`, and a new bucket every
    `resolution`. The defaults are nupic's, and so are the checks: an even
    number of active bits has no middle bit to shift, and too few positions
    leaves no room for the overlap rules.
    """
    if (active_bits' == 0) or ((active_bits' % 2) == 0) then error end
    if resolution' <= 0.0 then error end
    if positions' <= (6 * active_bits') then error end

    let random = Rand(seed)
    active_bits = active_bits'
    positions = positions'
    resolution = resolution'
    _random = random
    _buckets = Map[USize, Array[USize] val]

    let middle = _max_buckets / 2
    _lowest = middle
    _highest = middle

    // the one representation every other one is derived from: distinct bits
    // drawn from the whole width
    let chosen = Array[USize](active_bits)
    while chosen.size() < active_bits do
      let bit = random.int(positions.u64()).usize()

      var already = false
      for one in chosen.values() do
        if one == bit then already = true end
      end

      if not already then chosen.push(bit) end
    end

    let drawn: Array[USize] iso = recover iso Array[USize] end
    for one in chosen.values() do
      drawn.push(one)
    end
    _buckets(middle) = consume drawn

  fun width(): USize => positions

  fun ref encode(value: F64): Array[Bool] iso^ ? =>
    """
    The representation of this value. The first value seen sets the middle of
    the range, so the encoder needs no range in advance and never runs out of
    it in the direction that matters.
    """
    let bucket = _bucket_of(value)

    match _representation(bucket)?
    | let bits: Array[USize] val => _spread(bits)
    else
      error
    end

  fun bucket_of(value: F64): USize =>
    """
    Which bucket a value falls into. The first value seen is the middle bucket,
    so the middle is where the encoder was born rather than anywhere special.
    """
    match _offset
    | let seen: F64 =>
      let steps = ((value - seen) / resolution).round()
      let middle = (_max_buckets / 2).f64()
      let raw = middle + steps

      if raw <= 0.0 then
        return 0
      end

      let highest = (_max_buckets - 1).f64()
      if raw >= highest then return _max_buckets - 1 end

      raw.usize()
    else
      _max_buckets / 2
    end

  fun ref _bucket_of(value: F64): USize =>
    if _offset is None then
      _offset = value
    end
    bucket_of(value)

  fun ref _representation(bucket: USize): (Array[USize] val | None) ? =>
    if _buckets.contains(bucket) then
      return _buckets(bucket)?
    end

    if bucket < _lowest then
      if bucket == (_lowest - 1) then
        _add(bucket, _lowest)?
      else
        _representation(bucket + 1)?
        _representation(bucket)?
      end
    else
      if bucket == (_highest + 1) then
        _add(bucket, _highest)?
      else
        _representation(bucket - 1)?
        _representation(bucket)?
      end
    end

    _buckets(bucket)?

  fun ref _add(bucket: USize, from: USize) ? =>
    """
    Give a bucket the representation of its neighbour with one bit replaced, so
    that the two overlap in all but one bit.
    """
    let neighbour = _buckets(from)?

    if bucket < from then
      _lowest = bucket
    else
      _highest = bucket
    end

    match _replacement_of(neighbour, bucket)
    | let made: Array[USize] val => _buckets(bucket) = made
    end

  fun ref _replacement_of(neighbour: Array[USize] val, bucket: USize): (Array[USize] val | None) =>
    """
    Replace the one bit that moves between neighbours and accept the result once
    it satisfies the overlap rules.

    The reference retries without a bound. So does this: a limit would mean
    quietly accepting a representation that breaks the property the encoder
    exists for, which is worse than being slow.
    """
    let slot = bucket % active_bits

    while true do
      let candidate = _replaced(neighbour, slot, _random.int(positions.u64()).usize())
      if _acceptable(candidate, bucket) then return candidate end
    end

    None

  fun _replaced(neighbour: Array[USize] val, slot: USize, bit: USize): Array[USize] val =>
    let next: Array[USize] iso = recover iso Array[USize] end
    var index: USize = 0
    for existing in neighbour.values() do
      if index == slot then
        next.push(bit)
      else
        next.push(existing)
      end
      index = index + 1
    end
    consume next

  fun _acceptable(candidate: Array[USize] val, bucket: USize): Bool =>
    if candidate.size() != active_bits then return false end
    if not _all_different(candidate) then return false end

    for (index, other) in _buckets.pairs() do
      let apart =
        if index > bucket then index - bucket else bucket - index end
      let shared = _shared(candidate, other)

      if apart < active_bits then
        if shared != (active_bits - apart) then return false end
      else
        if shared > _max_overlap then return false end
      end
    end

    true

  fun _shared(left: ReadSeq[USize], right: ReadSeq[USize]): USize =>
    var shared: USize = 0
    for one in left.values() do
      if _contains(right, one) then shared = shared + 1 end
    end
    shared

  fun _all_different(bits: ReadSeq[USize]): Bool =>
    var index: USize = 0
    while index < bits.size() do
      var other: USize = index + 1
      while other < bits.size() do
        try
          if bits(index)? == bits(other)? then return false end
        end
        other = other + 1
      end
      index = index + 1
    end
    true

  fun _contains(bits: ReadSeq[USize], bit: USize): Bool =>
    for one in bits.values() do
      if one == bit then return true end
    end
    false

  fun _spread(bits: ReadSeq[USize]): Array[Bool] iso^ =>
    let encoded: Array[Bool] iso = recover iso Array[Bool] end
    var position: USize = 0
    while position < positions do
      encoded.push(_contains(bits, position))
      position = position + 1
    end
    consume encoded
