use "random"

primitive TieBreaker
  """
  A little fixed noise per column, so that columns claiming exactly as much as
  each other do not all lose to the lowest index.

  The reference adds this inside `InhibitColumns`: up to a hundredth, drawn once
  per column and kept for the pooler's life, added to that column's claim as the
  competition is decided. It is not variation between runs - the same seed gives
  the same values - only a rule for separating claims that would otherwise tie,
  which is what a pooler that has stopped moving produces constantly.

  A hundredth cannot overturn a claim that is genuinely stronger: an overlap is a
  count of matched bits, so two claims either differ by at least one or they are
  the same claim.
  """

  fun of(columns: USize, seed: U64): Array[F64] val =>
    """
    One value per column, each in `[0, 0.01)`.

    The generator is warmed up first. A freshly seeded one gives values that
    track the seed: with seed 1 the first two draws are 7e-9 and 0.13, so the
    same column would beat its neighbour for every small seed. Sixteen discarded
    draws are enough for it to forget where it started.
    """
    let random = Rand(seed)

    var wasted: USize = 0
    while wasted < 16 do
      random.int(2)
      wasted = wasted + 1
    end

    let noise: Array[F64] iso = recover iso Array[F64](columns) end

    var column: USize = 0
    while column < columns do
      noise.push(0.01 * random.real())
      column = column + 1
    end

    consume noise

  fun nudged(claims: Array[F64], noise: Array[F64] val): Array[F64] ? =>
    """
    The claims to compete with: each real claim nudged by its column's noise.

    A copy, so what a round remembers is still what the columns claimed. Noise
    decides between claims that are otherwise equal; it does not invent one, so
    a column that matched nothing is left claiming nothing.
    """
    let up: Array[F64] iso = recover iso Array[F64](claims.size()) end

    var column: USize = 0
    for claim in claims.values() do
      up.push(if claim > 0.0 then claim + noise(column)? else claim end)
      column = column + 1
    end

    consume up
