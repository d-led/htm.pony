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
the score for that step. Learning and scoring happen in the same pass, so there
is no training phase and the model is never frozen:

```pony
let detector = StreamingAnomalyDetector(pooler, memory)
let score = detector.observe(input)?
```

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
pooler wired it that way, not because anything is wrong. Two things carry
meaning:

- a **run** of high scores, where the pattern used to be steady;
- a **shift** in the distribution over a longer window.

A threshold on the raw score is a decision for whatever is consuming it. This
library does not set one, and does not smooth the score.

## What is not here

- **No likelihood.** Numenta's anomaly likelihood smooths the raw score over a
  rolling window and reports how unusual the score itself is. That is not
  written; only the raw score is.
- **No classification.** The third piece of the pipeline — learning which label
  a predicted state corresponds to — is not written, so the score says "this is
  unexpected" and not "this is the value that was expected".
- **A learning spatial pooler.** The columns are fixed at construction, so the
  same input always produces the same columns.
