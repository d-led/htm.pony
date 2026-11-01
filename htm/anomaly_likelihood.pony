use "./util"

class AnomalyLikelihood
  """
  How unusual an anomaly score is, given the scores that came before it.

  A raw anomaly score is a share of columns and means little on its own: where a
  third of every step bursts, four tenths is an ordinary step. This keeps the
  recent scores, smooths them, models them as a normal distribution, and says
  where the new one falls - nought in the middle of what it has seen, one far
  outside it.

  The first `learning_period + estimation_samples` scores are answered with a
  flat half, because a distribution estimated from ten points is not yet a
  distribution. After that the distribution is re-estimated every
  `reestimation_period` scores, over the retained history beyond the learning
  period.

  The reference also has a red-and-yellow filter for repeated alarms, which
  turns a run of high likelihoods into a lower one so that a dashboard is not
  permanently red. That is a display decision rather than part of the estimate,
  so it is not here: this reports the probability, and whoever shows it decides.
  """
  let _learning_period: USize
  let _probationary_period: USize
  let _historic_window: USize
  let _reestimation_period: USize
  embed _recent: _Rolling
  embed _history: _Rolling
  var _rounds: USize = 0
  var _distribution: (Normal | None) = None

  new create(
    learning_period: USize = 288,
    estimation_samples: USize = 100,
    historic_window: USize = 8640,
    reestimation_period: USize = 100,
    averaging_window: USize = 10) ?
  =>
    """
    The defaults are the reference's: about a day of five-minute samples to
    learn, a hundred to estimate from, and a re-estimate every hundred.
    """
    if (historic_window < estimation_samples) or (reestimation_period < 1) then
      error
    end

    _learning_period = learning_period
    _probationary_period = learning_period + estimation_samples
    _historic_window = historic_window
    _reestimation_period = reestimation_period
    _recent = _Rolling(averaging_window)
    _history = _Rolling(historic_window)

  fun ref observe(score: F64): F64 ? =>
    """
    Fold one score into the history and report how unusual it is.
    """
    _recent.push(score)?
    let smoothed = _recent.mean()?
    _history.push(smoothed)?

    _rounds = _rounds + 1
    if _rounds <= _probationary_period then return 0.5 end

    if (_distribution is None) or ((_rounds % _reestimation_period) == 0) then
      _distribution = _estimate()?
    end

    match _distribution
    | let normal: Normal => 1.0 - normal.tail_probability(smoothed)
    else 0.5
    end

  fun box fitted(): (this->Normal | None) =>
    """
    What the history currently looks like: where it sits and how far it spreads.
    Nothing until the learning period is over.
    """
    _distribution

  fun _estimate(): Normal ? =>
    let kept = _history.values()?
    let skipped = _skipped()

    let samples = Array[F64](kept.size() - skipped)
    var index = skipped
    while index < kept.size() do
      samples.push(kept(index)?)
      index = index + 1
    end

    Normal.estimate(samples)

  fun _skipped(): USize =>
    """
    How much of the retained history is still inside the learning period.

    The reference also allows for scores that have already fallen out of the
    window: once history is being forgotten, less of it is worth skipping.
    """
    let shifted_out =
      if _rounds > _historic_window then _rounds - _historic_window else 0 end
    let remaining =
      if _learning_period > shifted_out then _learning_period - shifted_out else 0 end

    if remaining < _rounds then remaining else _rounds end

class _Rolling
  """
  The last few values that were pushed, oldest first, at a fixed cost per value.
  """
  let _values: Array[F64]
  var _next: USize = 0
  var _filled: USize = 0

  new create(capacity: USize) =>
    _values = Array[F64].init(0.0, if capacity < 1 then 1 else capacity end)

  fun ref push(value: F64) ? =>
    _values(_next)? = value
    _next = (_next + 1) % _values.size()
    if _filled < _values.size() then _filled = _filled + 1 end

  fun size(): USize => _filled

  fun mean(): F64 ? =>
    if _filled == 0 then return 0.0 end

    var total: F64 = 0.0
    var index: USize = 0
    while index < _filled do
      total = total + _values(_position(index))?
      index = index + 1
    end
    total / _filled.f64()

  fun values(): Array[F64] ? =>
    let ordered = Array[F64](_filled)
    var index: USize = 0
    while index < _filled do
      ordered.push(_values(_position(index))?)
      index = index + 1
    end
    ordered

  fun _position(index: USize): USize =>
    (((_next + _values.size()) - _filled) + index) % _values.size()
