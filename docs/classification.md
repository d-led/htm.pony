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

## What it does not do

- **Values, not just labels.** Numenta's classifier also reports a distribution
  over buckets so it can predict a number and its error bar. This reports
  categories only.
- **Its own inputs.** It classifies whatever cells you hand it. Wiring it to the
  temporal memory's predicted cells, the way the anomaly score uses the bursts,
  is the caller's job.
- **Actors.** Like the temporal memory, it is a plain object.
