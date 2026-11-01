class val ImageFingerprint
  """
  What a picture reduces to before it becomes a representation: one bit per
  comparison, in a fixed order.

  The size is not fixed. Difference hashing gives 64 bits; a stronger hash such
  as PDQ gives 256 and needs no change here. What matters is that the same kind
  of picture gives bits in the same places, so that counting the bits two
  fingerprints disagree on measures how different the pictures are.
  """
  let _bits: Array[Bool] val

  new val create(bits: Array[Bool] val) =>
    _bits = bits

  new val from_u64(value: U64, bits: USize) =>
    """
    The low `bits` of a number, least significant first.
    """
    let extracted: Array[Bool] iso = recover iso Array[Bool].init(false, bits) end
    var index: USize = 0
    while index < bits do
      if (value and (U64(1) << index.u64())) != 0 then
        try extracted(index)? = true end
      end
      index = index + 1
    end
    _bits = consume extracted

  fun size(): USize => _bits.size()

  fun apply(index: USize): Bool ? =>
    _bits(index)?

  fun active(): USize =>
    """
    How many bits are set.
    """
    var count: USize = 0
    for bit in _bits.values() do
      if bit then count = count + 1 end
    end
    count

  fun hamming(that: ImageFingerprint val): USize ? =>
    """
    How many bits the two fingerprints disagree on.

    Zero means the same picture as far as the hash can tell. Fails when the two
    were produced by different hashes, because comparing them would mean
    nothing.
    """
    if size() != that.size() then error end

    var count: USize = 0
    var index: USize = 0
    while index < size() do
      if apply(index)? != that(index)? then count = count + 1 end
      index = index + 1
    end
    count

  fun string(): String iso^ =>
    let text = recover iso String end
    for bit in _bits.values() do
      text.push(if bit then '1' else '0' end)
    end
    consume text
