use "../../htm/encoders"

actor Main
  """
  A document encoder encodes the words a document is made of, not the document:
  each word is hashed over every position, the hashes are summed, and the
  positions with the highest totals are set.

  The point of doing it that way is what this prints - the overlap between every
  pair of documents below. Sentences that share words share positions, sentences
  that do not share almost none, and the two differ by how much of the sentence
  survived.
  """
  let _documents: Array[String] val = recover val [
    "the sky is beautiful today"
    "the sun is beautiful today"
    "the sky was beautiful yesterday"
    "the sky is not beautiful today"
    "who did my homework today"
  ] end

  new create(env: Env) =>
    try
      let encoder = SimHashDocumentEncoder(
        SimHashParams(400, 20
          where
            token_similarity' = false,
            case_sensitive' = false,
            frequency_ceiling' = 0,
            frequency_floor' = 0)?)

      env.out.print("a document as the positions its words vote for")
      env.out.print("")
      env.out.print(encoder.width().string() + " positions, 20 of them set"
        + " per document")
      env.out.print("")

      let encoded = _encode_each(env, encoder)?

      env.out.print("")
      _table(env, encoded)?

      env.out.print("")
      env.out.print("the same words are twenty positions, one word changed is"
        + " still most of them, and a different sentence is next to nothing")

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _encode_each(env: Env, encoder: SimHashDocumentEncoder)
    : Array[Array[Bool] val] ref ?
  =>
    """
    Every document, and how many positions its encoding sets.
    """
    let encoded: Array[Array[Bool] val] ref = Array[Array[Bool] val]
    for document in _documents.values() do
      let bits = encoder.encode(document)?
      env.out.print(_pad(document, 34) + _set(bits).string() + " positions set")
      encoded.push(bits)
    end
    encoded

  fun _table(env: Env, encoded: Array[Array[Bool] val] ref) ? =>
    """
    Every pair, row against column.
    """
    env.out.print("positions in common, row against column:")
    env.out.print(_pad("", 34) + "  1   2   3   4   5")

    var row: USize = 0
    for left in encoded.values() do
      row = row + 1
      env.out.print(_line(row, left, encoded)?)
    end

  fun _line(row: USize, left: Array[Bool] val, encoded: Array[Array[Bool] val] ref)
    : String ?
  =>
    var line: String = _pad(row.string() + " " + _documents(row - 1)?, 34)
    for right in encoded.values() do
      line = line + _pad(_shared(left, right)?.string(), 4)
    end
    line

  fun _set(bits: Array[Bool] val): USize =>
    var set: USize = 0
    for bit in bits.values() do
      if bit then set = set + 1 end
    end
    set

  fun _shared(left: Array[Bool] val, right: Array[Bool] val): USize ? =>
    var common: USize = 0
    var index: USize = 0
    while index < left.size() do
      if left(index)? and right(index)? then
        common = common + 1
      end
      index = index + 1
    end
    common

  fun _pad(text: String, width: USize): String =>
    var padded = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
