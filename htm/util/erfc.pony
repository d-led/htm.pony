// The approximation from Numerical Recipes, written out rather than called from
// a maths library. See docs/sources.md.
primitive Erfc
  """
  The complementary error function, `1 - erf(x)`: the share of a normal
  distribution more than `x` standard deviations from its middle.

  The standard library has no error function, so this is the approximation from
  Numerical Recipes. Its absolute error is below 1.2e-7 everywhere, which is far
  finer than anything an anomaly score needs, and it costs no dependency and no
  link to a maths library.

  It is written as Horner's rule for the same reason a polynomial is always
  written that way: the shape of the series stays visible instead of becoming a
  wall of parentheses.
  """

  fun of(x: F64): F64 =>
    let distance = x.abs()
    let t = 1.0 / (1.0 + (0.5 * distance))

    var series: F64 = 0.17087277
    series = -0.82215223 + (t * series)
    series = 1.48851587 + (t * series)
    series = -1.13520398 + (t * series)
    series = 0.27886807 + (t * series)
    series = -0.18628806 + (t * series)
    series = 0.09678418 + (t * series)
    series = 0.37409196 + (t * series)
    series = 1.00002368 + (t * series)

    let exponent = ((-(distance * distance) - 1.26551223) + (t * series))
    let answer = t * exponent.exp()

    if x >= 0.0 then answer else 2.0 - answer end
