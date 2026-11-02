use "collections"

class val SimHashParams
  """
  What a document encoding is made of.
  """
  let size: USize
  let active_bits: USize
  let token_similarity: Bool
  let case_sensitive: Bool
  let frequency_ceiling: USize
  let frequency_floor: USize
  let excludes: Array[U64] val

  new val create(
    size': USize,
    active_bits': USize,
    token_similarity': Bool = false,
    case_sensitive': Bool = false,
    frequency_ceiling': USize = 0,
    frequency_floor': USize = 0,
    excludes': Array[String] val = recover val Array[String] end) ?
  =>
    """
    `size'` positions, `active_bits'` of them set, and the few choices that
    decide what a token is.

    `token_similarity'` also brings in each letter of a token, so that "cat" and
    "cats" end up near each other. That is what makes a document encoder useful
    for plurals and misspellings, and it costs document-level sharpness: the
    letters blur the tokens they belong to.

    `frequency_ceiling'` stops one repeated word from deciding the whole
    encoding; `frequency_floor'` makes a word that appears once count as if it
    appeared that many times. Both are counts, and zero means the rule is off.

    `excludes'` are words to ignore, for the ones every document in the corpus
    has and that therefore say nothing about any of them.
    """
    if size' == 0 then error end
    if (active_bits' == 0) or (active_bits' > size') then error end
    if (frequency_ceiling' > 0) and (frequency_floor' > frequency_ceiling') then
      error
    end

    size = size'
    active_bits = active_bits'
    token_similarity = token_similarity'
    case_sensitive = case_sensitive'
    frequency_ceiling = frequency_ceiling'
    frequency_floor = frequency_floor'

    let ignored: Array[U64] iso = recover iso Array[U64] end
    for word in excludes'.values() do
      ignored.push(TokenDigest.of(word, 0, word.size(), case_sensitive')?)
    end
    excludes = consume ignored

class SimHashDocumentEncoder
  """
  Encodes a document as the words it is made of: each word is hashed over every
  position, the hashes are summed with a vote per position, and the positions
  with the highest totals are the ones that end up set.

  This is SimHash, the locality-sensitive hash that finds near-duplicate web
  pages. What makes it an encoder rather than a hash is the last step: a full
  SimHash would keep every position whose total is positive, and the result would
  be half set, which no spatial pooler wants. Taking the top `active_bits`
  instead keeps the encoding sparse while keeping the property that matters:
  documents that share words share positions.

  Two documents with the same words encode identically. One word swapped for
  another costs that word's votes, and only positions where the swapped words
  were the ones deciding change, so similar documents end up similar - by
  overlap, which is the only relation a spatial pooler can see.

  The rules are `SimHashDocumentEncoder` from `htm.core`: whitespace-separated
  tokens, tokens folded to lower case unless asked otherwise, weights from how
  often a word occurs, and the top N sums. The digest behind it is this library's
  rather than that one's (see `TokenDigest`), and the vocabulary weighting and
  serialisation that encoder also offers are not ported.
  """
  let _params: SimHashParams
  let _excluded: Set[U64] val

  new create(params: SimHashParams) =>
    _params = params

    let excluded: Set[U64] iso = recover iso Set[U64] end
    for word in params.excludes.values() do
      excluded.set(word)
    end
    _excluded = consume excluded

  fun width(): USize =>
    """How many positions the encoding has."""
    _params.size

  fun encode(document: String): Array[Bool] val ? =>
    """
    The document, as `size` bits with `active_bits` of them set.

    A document with no words encodes to nothing rather than to an arbitrary part
    of the vector: an empty document is not similar to a document, and the
    positions it would have been given would say otherwise.
    """
    let sizes = _params.size
    let weights = _weights(document)?

    if weights.size() == 0 then
      return _blank()
    end

    let sums: Array[I64] ref = Array[I64](sizes)
    var position: USize = 0
    while position < sizes do
      sums.push(0)
      position = position + 1
    end

    for (seed, weight) in weights.values() do
      _vote(sums, seed, weight)?
    end

    _encode_sums(sums)?

  fun _blank(): Array[Bool] val =>
    """Every position off: what a document with no words in it encodes to."""
    let blank: Array[Bool] iso = recover iso Array[Bool](_params.size) end
    var position: USize = 0
    while position < _params.size do
      blank.push(false)
      position = position + 1
    end
    consume blank

  fun _weights(document: String): Array[(U64, USize)] ref ? =>
    """
    One weight per distinct word in the document, and one per letter if letters
    are being counted.

    The word is identified by its digest, so a document never becomes a second
    string: the tokens are spans of the one it came in as.
    """
    let counts: Map[U64, USize] = Map[U64, USize]
    let texts = Spans.of(document)?

    for (from, to) in texts.values() do
      _count(counts, TokenDigest.of(document, from, to, _params.case_sensitive)?)

      if _params.token_similarity then
        var index = from
        while index < to do
          _count(counts, TokenDigest.of_letter(document(index)?,
            _params.case_sensitive))
          index = index + 1
        end
      end
    end

    let weights: Array[(U64, USize)] ref = Array[(U64, USize)]
    for (seed, seen) in counts.pairs() do
      var weight = seen
      if (_params.frequency_ceiling > 0) and (weight > _params.frequency_ceiling)
      then
        weight = _params.frequency_ceiling
      end
      if weight < _params.frequency_floor then
        weight = _params.frequency_floor
      end
      weights.push((seed, weight))
    end
    weights

  fun _count(counts: Map[U64, USize] ref, seed: U64) =>
    if _excluded.contains(seed) then return end
    counts.update(seed, (try counts(seed)? else 0 end) + 1)

  fun _vote(sums: Array[I64] ref, seed: U64, weight: USize) ? =>
    """
    One word's contribution: every position it has set gains `weight`, every
    position it has unset loses the same.
    """
    let bits = TokenDigest.bits(seed, _params.size)
    let vote = weight.i64()

    var index: USize = 0
    for bit in bits.values() do
      sums.update(index, (sums(index)? + if bit then vote else -vote end))?
      index = index + 1
    end

  fun _encode_sums(sums: Array[I64] ref): Array[Bool] val ? =>
    """
    The positions with the highest totals, as a bit vector.

    Picking the largest and then pushing it out of the way is how `htm.core`
    does it. Positions that tie are settled by the lower position winning, so
    the same document always gets the same bits.
    """
    let encoded: Array[Bool] iso = recover iso Array[Bool](_params.size) end
    var position: USize = 0
    while position < _params.size do
      encoded.push(false)
      position = position + 1
    end

    var picked: USize = 0
    while picked < _params.active_bits do
      let best = _highest(sums)?
      encoded.update(best, true)?
      sums.update(best, I64.min_value())?
      picked = picked + 1
    end

    consume encoded

  fun _highest(sums: Array[I64] box): USize ? =>
    var best: USize = 0
    var highest: I64 = sums(0)?

    var index: USize = 1
    while index < sums.size() do
      let total = sums(index)?
      if total > highest then
        highest = total
        best = index
      end
      index = index + 1
    end

    best
