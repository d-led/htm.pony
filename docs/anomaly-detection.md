# Streaming anomaly detection

An anomaly is a prediction that failed. The temporal memory predicts which cells
will be active at the next step; a column that turns out active without having
been predicted has to burst. So the share of active columns that burst is a
direct measure of how surprising the input was:

```
anomaly = bursting columns / active columns
```

Zero means everything that happened was expected. One means nothing was.

## Online, not trained first

`StreamingAnomalyDetector` folds one input at a time into the model and returns
the score for that step. The memory learns and scores in the same pass, so there
is no training phase and the memory is never frozen:

```pony
let detector = StreamingAnomalyDetector(pooler, memory)
let score = detector.observe(input)?
```

The pooler is the exception. It is used exactly as it was handed over and is not
trained by the detector, because a representation that kept moving would move the
thing the memory is trying to learn. A caller that wants the representation to
adapt as well drives the pooler directly and hands the detector one it controls.

That is what makes it work on a stream: the thing it is measuring changes as it
learns, which is also why the first steps score badly. Nothing is expected
before anything has been seen.

## What the example shows

[The anomaly stream example](examples.md#anomaly-detection) repeats three inputs
and then breaks the pattern:

```
eight rounds of a b c, then d

a  ####################  1
b  ####################  1
c  ####################  1
a  ####################  1
b  ....................  0
c  ....................  0
...
a  ....................  0
b  ....................  0
c  ....................  0

d  ####################  1
```

The first four steps are unsurprising in the literal sense: nothing has been
learned, so every column bursts. By the fifth step the sequence is known and the
score falls to zero. The input that was never seen bursts every column and scores
one.

## Reading the numbers honestly

A single score is noisy. A column can light up differently because the spatial
pooler wired it that way, not because anything is wrong. A threshold on the raw
score is a decision for whatever is consuming it, and this library does not set
one.

What it does instead is [say how unusual the score itself is](#the-likelihood).

## The likelihood

`AnomalyLikelihood` answers "given the scores that came before, how strange is
this one". It keeps the recent scores, smooths them, models them as a normal
distribution and reports one minus the probability of a score that far out:
near the middle of what it has seen, about a half; far outside it, one.

The example feeds it two hundred ordinary scores that wobble a little, then one
that does not:

```
its idea of ordinary: centred at 0.151, spreading 0.017

step                    score   likelihood
an ordinary step       0.141   0.57
another ordinary step  0.183   0.517
the odd step           0.9     1

the noisiest ordinary likelihood in two hundred steps was 0.908
only the odd step comes near certainty
```

Three things about those numbers are worth knowing before trusting them.

**An ordinary step is not near zero.** The value is one minus a tail
probability, so half of all ordinary steps read above a half. An alarm wants a
threshold near `0.999`, not near `0.5`. The noisiest of the two hundred ordinary
steps above read 0.908, which is what a run of scores with a narrow spread looks
like.

**The first `learning_period + estimation_samples` scores read a flat half.**
A distribution from ten points is not a distribution. The defaults are the
reference's: 288 to learn and 100 to estimate from, which at five-minute
samples is about a day and a half of a stream before anything is judged.

**A perfectly predicted stream is a degenerate case.** If every score is
exactly zero, the estimator's variance floor takes over and the smallest
movement in the raw score becomes a certainty. The reference has the same floor,
and the same consequence: the likelihood is meant for streams that vary.

### Using the two together

The detector and the likelihood are separate objects on purpose: the score is a
property of one step, and the likelihood is a property of a stream of them. They
compose in three lines.

```pony
let detector = StreamingAnomalyDetector(pooler, memory)
let likelihood = AnomalyLikelihood()?

let score = detector.observe(input)?       // the share of columns that burst
let strange = likelihood.observe(score)?   // how unusual that share is
```

The defaults on the likelihood mean nothing is judged for the first 388 steps.
For a short demonstration, hand it smaller periods:

```pony
AnomalyLikelihood(10, 10, 200, 5, 10)?   // learn, estimate, keep, re-estimate, smooth
```

### What is not ported

The reference filters runs of high likelihood down to a lower value so that a
dashboard is not permanently red. That is a display decision rather than part of
the estimate, so it is not here.

## What is not here

- **No classification.** The third piece of the pipeline — learning which label
  a predicted state corresponds to — is not written here, though the [SDR
  classifier](classification.md) does that part on its own.
- **Learning on actors.** The columns learn in process, so the whole pipeline is
  in process.
