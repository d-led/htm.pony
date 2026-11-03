# Temporal pooler

A [temporal memory](temporal-memory.md) learns that one pattern follows another.
A temporal pooler learns the same thing and answers a different question: not
"which cell will be active next", but "which of the situations I have been in
does this belong to, and what tends to come out of them".

That difference is small to say and large in what follows. A memory keeps one
path through the sequences it has seen, and a burst throws the path away. A
pooler keeps the *union* of the situations that led to a step, so it can be in
several of them at once, and it does not lose the sequence when an input arrives
that it did not expect.

It is implemented and tested in process and on actors, and it is the last piece
of the reference algorithm
([htm-community/htm](https://github.com/htm-community/htm)'s `temporalPooler.go`)
to be ported.

## The same cells, a different question

The pooler is built from the same parts as the memory: nodes (the pooler's word
for a column, since a pooled state is no longer about one column's input), cells
inside them, and segments on the cells that reach other cells. Two cells of a
node are enough for the tests, and the reference's `cellsPerColumn` of 32 is what
a real population wants.

What differs is what a segment is asked. In a pooler a segment answers two
things:

- how much of the state it reaches, counting every synapse however weak, which is
  what `activity` is
- whether that is enough *connected* synapses to predict, which is what `active`
  is

Both are needed because the pooler learns from the difference. A segment that
reaches a lot of the state but not enough to predict is still evidence, and it
earns the cell some of the pooler's confidence - which is why a pooler can say
how sure it is, not only what it expects.

## What pooling adds

With `pooling` on, a cell that predicted also learns the state one step *before*
the one that taught it, on the segment of its node that matches that step. Two
consequences, and both are what makes this a CLA rather than a sequence memory:

- a pooled cell is woken by a longer context than the one that predicted it, so
  the state a node settles on is a union of contexts rather than a single path
- a pattern predicts not only what followed it but what followed *that*

The second is measurable and is in the tests: with a window of one, a pooling
pooler predicts the next two patterns where a plain one predicts the next. With
the reference's default window of five over a five-pattern cycle the prediction
widens to two thirds of the population, because a kept proposal lives for a whole
cycle and is then applied at the wrong phase - so the pooled tests use a window
of one, and [the handoff](../handoff.md) says why nobody should tune that
silently. [What the pooler's settings are worth](../examples.md#what-the-poolers-settings-are-worth)
has the measured numbers on a ten-pattern cycle: 10, 20 and 28 nodes named a step
for plain, window one and window five, at 290, 490 and 580 segments.

## One step

```
input columns --> activate: the predicted cells, or the whole node when there
                            are none
                       |
              predict: every segment that reaches enough of the state, with the
                       confidence it has earned
                       |
              learn:  judge the proposals queued last step, activate, decide
                      whether the sequence held, queue this step's proposals
```

Two passes, in that order, and the second cannot be folded into the first: a
prediction is about a state that includes what happens after the activation the
first pass decided.

## Losing a sequence, and finding it again

Neither pass knows where a sequence began. If the pooler is shown the middle of a
sequence it has learned, the first input is unexpected, and bursting it would
throw away the context that the rest of the sequence provides.

So the recent inputs are kept, and an unexpected step is re-played: for each of
the last inputs in turn, farthest back first, the pooler assumes the sequence
began there, walks forward from that input's start cells, and asks whether it
still predicts the input that arrived. The farthest start that survives wins,
because context is what a prediction is made of. When none survives, the step
bursts exactly as it would have.

The learning pass does the same thing for a different reason - it has to begin a
sequence when the PAM counter expires or the length limit is reached, and
beginning on start cells throws away the step before the seam, so a sequence
learned in pieces never joins up.

The [recovery example](../examples.md#a-pooler-that-lost-its-sequence-and-found-it-again)
shows the difference in one number: ten active cells, one a node, rather than the
twenty a burst would turn on.

## What it says about the future

`predict(steps)` answers a `ClaForecast`: the confidence the pooler would put on
every node at each of the next steps, with `nodes(step)` naming the ones that
carry any. The first step comes from the state it is in; each one after that is
read from a state rolled forward with no input of its own, where what was
predicted becomes the activity. The state is put back before the answer is
returned, so asking what comes next does not decide it.

`node_confidences()` is the same soft answer for the step it is on: the
confidence per node rather than the nodes a threshold lets through, and it is
also in the `ClaOutput` a step answers with.

## Using it

```pony
let pooler = TemporalPooler(TemporalPoolerConfig(50, 2 /* ... */)?, seed = 7)

pooler.compute(active_columns, learn = true, infer = false)?   // teach
pooler.reset()                                                 // a sequence ended
pooler.compute(active_columns, learn = false, infer = true)?   // ask
pooler.predicted_columns()   // the nodes it expects next
pooler.predict(3)?           // ... and for the two steps after that
```

On actors the same steps are messages, and the answer arrives as a value:

```pony
let pooler = TemporalPoolerActor(config, seed = 7)
pooler.compute(active_columns, learn, infer, an_observer)   // a step
pooler.predict(3, a_forecaster)                             // three steps ahead
```

Both forms answer the same questions - a step, and a forecast - which is the
rule every actor form in this library is held to.

One actor rather than a set of shards, and that is a finding rather than a
shortcut: a memory's segment reaches cells of its own column only, so its columns
split cleanly between shards, while a pooler's segment reaches across nodes and
its prediction is decided by scanning the whole population. [Actors](../actors.md#the-cla-temporal-pooler-on-actors)
has the rest.

## What is not here

- **The pooled representation as a hierarchy.** The reference's pooling is the
  one-step-further-back learning above, and it is ported. Its `Predict` of a
  layered region, where a pooled output feeds the next region, is not: nothing
  here stacks two poolers.
- **Sequence ids and shared cells across layers**, which some HTM
  implementations add on top. The reference does not have them and neither does
  this.
- **A confident threshold on the forecast.** `predict` reports the confidence it
  has; deciding that a node is "predicted enough" is the caller's business, and
  the tests read it as any node with a non-zero share.
