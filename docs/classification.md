# Classification

`SDRClassifier` turns an active set of cells into a probability for each
category. The temporal memory says which cells it expects; this says what those
cells have meant so far.

It is one layer and deliberately no more. The representation already does the
work — the memory's cells are the feature — so the classifier only has to learn
which feature means which label.

## Using it

```pony
let classifier = SDRClassifier(categories = 3, inputs = memory.cells())?

// learn what the active cells meant
classifier.compute(active_cells, category = 1, learn = true)?

// ask what they mean
let probabilities = classifier.compute(active_cells, None, false)?
classifier.best()   // the most likely category
```

Each input bit carries one weight per category. A category's score is the sum of
the weights of the bits that are active, and the scores become probabilities
through a softmax. Learning moves every active bit's weight towards the category
that turned out to be true and away from the others, in the same pass as
inference.

## Classifying a prediction, not a present

Fed the cells that are active, a classifier describes the present. Fed the cells
that are *predicted*, it says what comes next - and it can say so before the next
input arrives.

`PredictionClassifier` is that pairing:

```pony
let predictor = PredictionClassifier(memory, 3)?

// one step at a time, with the label that step turned out to be
let probabilities = predictor.observe(columns, label, true)?
predictor.best()   // what the next step is expected to be
```

The bookkeeping is the whole of the class. A prediction is made at one step and
the label that tests it arrives at the next, so it learns on the previous step's
expectation with the current step's label, and reports the new expectation.

The test that matters is that the label of the next step is named before that
step is shown.

## More than one step ahead

A predictor built with more steps keeps one classifier per step and the last
`steps` expectations. The classifier for step k is taught by the expectation made
k steps back and is asked about the newest one, so the cells it reads at
inference are the ones it was taught on:

```pony
let ahead = PredictionClassifier(memory, 3, 0.1, 2)?

ahead.observe(columns, label, true)?
ahead.best_at(1)?   // what comes next
ahead.best_at(2)?   // what comes after that
```

Asking beyond what it was built for is an error rather than a zero: a number
nobody computed would look like a prediction with no confidence behind it.

## What it does not do

- **Values, not just labels.** Numenta's classifier also reports a distribution
  over buckets so it can predict a number and its error bar. This reports
  categories only.
- **Its own inputs.** It classifies whatever cells you hand it. Wiring it to the
  temporal memory's predicted cells, the way the anomaly score uses the bursts,
  is the caller's job.
- **Actors.** Like the temporal memory, it is a plain object.
- **A sequence model of its own.** Each step ahead is its own table of weights;
  there is no recurrence and nothing shared between them beyond the memory the
  expectations come from.
