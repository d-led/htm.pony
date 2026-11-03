# Temporal memory

The spatial pooler answers "what is this". The temporal memory answers "what
usually comes next". It takes the active columns of one step, compares them with
what it remembers about the step before, and says which cells it expects to be
active at the next one.

It is implemented and tested in process, and as actors: a `TemporalRegion` holds
the columns in shards and runs a step as two passes over them. It is given the
columns of a [spatial pooler](../spatial-pooler.md#learning) that learns its
permanences in process rather than on actors.

When a memory keeps losing the sequence it is following, what is wanted is the
[next page](temporal-pooler.md) rather than this one.

## Why it needs cells

A column is either active or not, so it cannot distinguish two situations in
which it is active. Sequence learning needs exactly that distinction: the same
column fires in many contexts, and what follows differs between them.

That is what [cells](columns-and-cells.md) are for. A column holds several cells,
and which of them is active records the context. The references express this with
`cellsPerColumn`, which `htm.core` defaults to 32.

A cell owns **segments**. A segment holds synapses onto other cells, and it is
active when enough of those cells were active at the previous step. A cell with
an active segment is the memory's prediction.

## One step

```
columns ---------> which cells were predicted for those columns?
                        |
             yes: activate only those cells
              no: activate every cell in the column, and call it a burst
                        |
             learn: move the synapses of the segments that were right
                    grow a new segment where nothing predicted
```

A **burst** is a column that was not predicted. It activates all of its cells,
because the memory does not know which one applies, and it learns a segment for
the situation that preceded it.

A burst also has to pick **one** cell to be the one the situation belongs to -
the cell whose segment came closest, or a cell that has learned least, where a
new segment is grown. That cell is the column's *winner* for the step, and the
next step grows its new synapses to the winners and not to every cell that was
active. The difference is easy to miss and expensive to get wrong: a burst lights
up every cell of its column, so a segment that reached all of them and was then
capped at `max_synapses` would be wired to a mix of the two offsets, and would
reach only half its synapses the moment the state arrives as a prediction rather
than a burst. With winners, a learned sequence is followed at every step instead
of alternating with bursts.

*Least used* rather than always the first cell, because a cell holds a few
segments and a column that arrives after two different states needs one segment
for each. Growing every new segment on the first cell made the second context
overwrite the first: the column then burst every other time the state arrived
and could never settle. This is also what the reference does - it draws one of
the least-used cells at random, where this port takes the lowest index so that a
run can be repeated.

A segment that was active and whose cell then did not become active was wrong,
and its synapses towards the cells that were active move away from connection.
Without that, a segment keeps the synapses it was born with forever, including
the ones pointing at cells that never fire again, and those hold its match count
down.

## Using it

```pony
let memory = TemporalMemory(TemporalMemoryParams(
  where columns' = 64, cells_per_column' = 32))?

let output = memory.compute(active_columns, true)?
output.active_cells      // what is active now
output.predictive_cells  // what it expects next
output.bursting_columns  // the columns it had no prediction for
```

Every setting is named because a memory is nine numbers otherwise: `columns'`,
`cells_per_column'`, `activation_threshold'`, the two permanence thresholds and
the two steps it takes, and the two limits on what one cell may hold. Named
arguments may be given in any order, so only the ones that differ from the
defaults need to appear at all.

`predictive_cells` describes the future, not the present: it is computed from the
cells that just became active, so it says what the memory expects at the next
step.

The example in [examples](../examples.md#prediction) teaches one column to follow
another and then shows that the second no longer bursts.

## The anomaly reading

A burst is a prediction that failed. The share of active columns that burst is
therefore a direct measure of how surprising the input was, and it is what
streaming anomaly detection reads:

```
anomaly = bursting columns / active columns
```

Zero means everything that happened was expected. One means nothing was.

That number is also how the value of the pooler's learning shows up. [What a
learned pooler gives the memory](../examples.md#what-a-learned-pooler-gives-the-memory)
runs one cycle of symbols through a memory over a pooler that learned the symbols
and through a memory over one that only looked, then knocks a bit out of every
symbol: the learned pooler leaves the sequence far easier to follow.

## What is not here

- **Segment reuse over long runs.** A column that keeps bursting and never
  matches grows a new segment until it hits `max_segments_per_cell`, and then
  stops learning.
- **More than one kind of sequence.** The study measures one cycle of symbols and
  one way of damaging them, so the size of the effect it reports is not a
  constant to carry to another stream.
- **A pooled state.** A memory bursts a column and starts again; keeping the
  union of the situations that led to a step is the
  [temporal pooler](temporal-pooler.md), which is a different class rather than a
  setting on this one.
