use "random"
use "collections"

class val ImageEncoder
  """
  Turns a picture into a sparse representation, so that similar pictures give
  overlapping ones.

  A value, so it can be built once and handed to whatever actor does the work -
  the positions it draws are its whole state and nothing moves them.

  A fingerprint on its own is not a representation. It is about half set bits,
  it is far too short to fill a column population, and two fingerprints that
  differ in one bit are simply different - there is no graded similarity to
  read off them.

  So each fingerprint bit owns one position in the representation, and the
  representation is those positions for the bits that are set. Two fingerprints
  that disagree on `k` bits then share all but `k` of their active positions,
  and the share falls away as the pictures get less alike. Counting the
  positions two representations have in common is the same as counting the bits
  two fingerprints agree on.

  The positions are drawn once, in the constructor, without repetition: two
  fingerprint bits never own the same position, so no two pictures share an
  active position by accident.
  """
  let params: ImageEncoderParams val
  let _positions: Array[USize] val

  new val create(params': ImageEncoderParams val) ? =>
    if params'.bits == 0 then error end
    if params'.width < params'.bits then error end

    let random = Rand(params'.seed)
    let positions: Array[USize] iso = recover iso Array[USize] end
    let taken = Set[USize]

    while positions.size() < params'.bits do
      let candidate = random.int(params'.width.u64()).usize()
      if not taken.contains(candidate) then
        taken.set(candidate)
        positions.push(candidate)
      end
    end

    params = params'
    _positions = consume positions

  fun encode(image: GrayscaleImage val): Array[Bool] ? =>
    """
    The representation of a picture.
    """
    encode_fingerprint(DifferenceHash.compute(image)?)?

  fun encode_fingerprint(fingerprint: ImageFingerprint val): Array[Bool] ? =>
    """
    The representation of a fingerprint the caller already has.

    Fails when the fingerprint is not the size this encoder was built for.
    """
    if fingerprint.size() != params.bits then error end

    let result = Array[Bool].init(false, params.width)

    var bit: USize = 0
    while bit < params.bits do
      if fingerprint(bit)? then
        result(_positions(bit)?)? = true
      end
      bit = bit + 1
    end

    result

  fun overlap(left: ReadSeq[Bool], right: ReadSeq[Bool]): USize =>
    """
    How many positions two representations have in common.
    """
    var count: USize = 0
    var index: USize = 0
    let shortest = if left.size() < right.size() then left.size() else right.size() end
    while index < shortest do
      try
        if left(index)? and right(index)? then count = count + 1 end
      end
      index = index + 1
    end
    count
