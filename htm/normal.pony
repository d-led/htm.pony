// Follows the NuPIC line's normal estimate, including its lower bounds on the
// mean and the spread.
use "./util"

class Normal
  """
  A normal distribution: where its samples sit, and how far they spread.

  `estimate` is how one is obtained from data. It keeps the reference's lower
  bounds, which are not decoration: a stream of near-zero anomaly scores has a
  spread of almost nothing, and without a floor the first point that moved by a
  hair would be reported as a certainty.

  The class is a value in spirit - nothing here is ever changed - but it is
  estimated from an array the caller owns, and a `val` class cannot accept one.
  """
  let mean: F64
  let spread: F64

  new create(mean': F64, spread': F64) =>
    mean = mean'
    spread = spread'

  new estimate(samples: ReadSeq[F64]) =>
    var total: F64 = 0.0
    for sample in samples.values() do
      total = total + sample
    end

    let count = samples.size().f64()
    let average = if samples.size() == 0 then 0.0 else total / count end

    var squares: F64 = 0.0
    for sample in samples.values() do
      let gap = sample - average
      squares = squares + (gap * gap)
    end
    let variance = if samples.size() == 0 then 0.0 else squares / count end

    mean = if average < 0.03 then 0.03 else average end
    spread = (if variance < 0.0003 then 0.0003 else variance end).sqrt()

  fun tail_probability(x: F64): F64 =>
    """
    How likely a sample is to sit at least as far from the middle as `x`, in
    either direction: a half at the middle, nothing at the far edges.

    The reference flips a value below the mean around the mean and calls itself
    again; the answer is the same as asking about the distance, which is what
    this asks. It writes the root of two as 1.4142, losing a digit of accuracy on
    the way to the same answer; this does not.
    """
    if spread <= 0.0 then
      return if x == mean then 0.5 else 0.0 end
    end

    0.5 * Erfc.of((x - mean).abs() / (spread * 1.4142135623730951))
