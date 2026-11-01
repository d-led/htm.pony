use "random"
use "../../htm"

actor Main
  """
  Raw anomaly scores turned into a probability.

  Nothing here is an HTM: the scores are made up, because the point is what the
  estimator does to a score rather than where the score came from. Two hundred
  steps of ordinary scores wobble around 0.15; then one step of 0.9 arrives.

  A raw score of 0.15 means nothing by itself. Read against what came before it,
  it is a perfectly ordinary step, and the 0.9 is not.
  """
  new create(env: Env) =>
    try
      let estimator = AnomalyLikelihood(50, 20, 400, 20, 10)?
      let random = Rand(11)

      env.out.print("two hundred ordinary steps, then one that is not")
      env.out.print("")

      var round: USize = 0
      var worst: F64 = 0.0
      while round < 200 do
        let score = _ordinary(random)
        let likelihood = estimator.observe(score)?
        if likelihood > worst then worst = likelihood end
        round = round + 1
      end

      match estimator.fitted()
      | let normal: Normal =>
        env.out.print("its idea of ordinary: centred at " + _near(normal.mean)
          + ", spreading " + _near(normal.spread))
      end

      env.out.print("")
      env.out.print("step                    score   likelihood")
      _line(env, "an ordinary step", _ordinary(random), estimator)
      _line(env, "another ordinary step", _ordinary(random), estimator)

      let spike = estimator.observe(0.9)?
      _print(env, "the odd step", 0.9, spike)

      env.out.print("")
      env.out.print("the noisiest ordinary likelihood in two hundred steps was "
        + _near(worst))

      if spike > 0.99 then
        env.out.print("only the odd step comes near certainty")
        env.exitcode(0)
      else
        env.out.print("the odd step did not stand out: " + _near(spike))
        env.exitcode(1)
      end
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _ordinary(random: Rand): F64 =>
    """
    A score that wobbles, the way a real one does: no stream is ever perfectly
    predicted, and an estimator with nothing to measure has nothing to say.
    """
    0.10 + (random.real() * 0.10)

  fun _line(env: Env, name: String, score: F64, estimator: AnomalyLikelihood) =>
    try
      _print(env, name, score, estimator.observe(score)?)
    end

  fun _print(env: Env, name: String, score: F64, likelihood: F64) =>
    env.out.print(_pad(name, 23) + _pad(_near(score), 8) + _near(likelihood))

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded

  fun _near(value: F64): String =>
    ((value * 1000.0).round() / 1000.0).string()
