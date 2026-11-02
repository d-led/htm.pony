use "collections"

primitive TokenDigest
  """
  A digest of one token, spread over as many bits as the encoding is wide.

  FNV-1a over the token's bytes, then a finaliser that lets a one-letter change
  move every bit of the result, then a stream of 64-bit words derived from it.
  This is not a cryptographic hash and it does not need to be: what SimHash asks
  of a digest is that two different tokens look nothing alike and that one token
  always looks the same. Both hold.

  `htm.core`, whose encoder this follows, squeezes a SHAKE256 digest of the token
  instead. Neither the words nor the bits agree with that one, which matters only
  if encodings from the two libraries are compared, and they are not: an encoding
  is read against another encoding from the same encoder.
  """
  fun of(text: String, from: USize, to: USize, case_sensitive: Bool): U64 ? =>
    """
    The digest of the token that occupies `text` from `from` up to `to`, with
    capitals folded onto lower case unless the caller wants them apart. Folding
    here rather than in a copy of the token is why no token is ever a string of
    its own.
    """
    var hash: U64 = 0xcbf29ce484222325
    var index: USize = from
    while index < to do
      hash = (hash xor _folded(text(index)?, case_sensitive).u64())
        *~ 0x100000001b3
      index = index + 1
    end
    _mixed(hash)

  fun of_letter(byte: U8, case_sensitive: Bool): U64 =>
    """The digest of a single character, for encodings that bring letters in."""
    _mixed(0x9E3779B97F4A7C15 xor _folded(byte, case_sensitive).u64())

  fun bits(seed: U64, width: USize): Array[Bool] val =>
    """
    One bit per position, in the order the words of the digest arrive.

    The same seed gives the same bits, which is the point: two documents that
    share a token share that token's bits, and the sums are where they meet.
    """
    let spread: Array[Bool] iso = recover iso Array[Bool](width) end
    var state = seed
    var word: U64 = 0
    var left: USize = 0

    var placed: USize = 0
    while placed < width do
      if left == 0 then
        state = state +~ 0x9E3779B97F4A7C15
        word = _mixed(state)
        left = 64
      end
      spread.push((word and 1) == 1)
      word = word >> 1
      left = left - 1
      placed = placed + 1
    end

    consume spread

  fun _mixed(value: U64): U64 =>
    """
    The finaliser of SplitMix64: three xor-shifts with multiplications between
    them, so that neighbouring inputs give unrelated outputs.
    """
    var mixed = value +~ 0x9E3779B97F4A7C15
    mixed = (mixed xor (mixed >> 30)) *~ 0xBF58476D1CE4E5B9
    mixed = (mixed xor (mixed >> 27)) *~ 0x94D049BB133111EB
    mixed xor (mixed >> 31)

  fun _folded(byte: U8, case_sensitive: Bool): U8 =>
    if case_sensitive then
      byte
    elseif (byte >= 65) and (byte <= 90) then
      byte + 32
    else
      byte
    end

primitive Spans
  """
  Where the tokens of a document are: the runs of text between whitespace.
  """
  fun of(text: String): Array[(USize, USize)] ref ? =>
    let spans: Array[(USize, USize)] ref = Array[(USize, USize)]
    var start: USize = 0
    var in_token: Bool = false

    var index: USize = 0
    while index < text.size() do
      if _is_space(text(index)?) then
        if in_token then
          spans.push((start, index))
          in_token = false
        end
      elseif not in_token then
        start = index
        in_token = true
      end
      index = index + 1
    end

    if in_token then
      spans.push((start, text.size()))
    end

    spans

  fun _is_space(byte: U8): Bool =>
    (byte == 32) or (byte == 9) or (byte == 10) or (byte == 13)
