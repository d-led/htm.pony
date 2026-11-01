# Temporal memory

The spatial pooler answers "what is this". The temporal memory answers "what
usually comes next". It takes the active columns of one step, compares them with
what it remembers about the step before, and says which cells it expects to be
active at the next one.

It is implemented and tested in process. It does not run as actors yet, and the
spatial pooler still does not learn, so the columns it is given never change.

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

## Using it

```pony
let memory = TemporalMemory(TemporalMemoryParams(columns = 64, cells_per_column = 32))?

let output = memory.compute(active_columns, learn = true)?
output.active_cells      // what is active now
output.predictive_cells  // what it expects next
output.bursting_columns  // the columns it had no prediction for
```

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

## What is not here

- **Actors.** The memory is a plain object. Running it on actors, the way the
  spatial pooler already does, has not been done.
- **Punishing wrong segments.** Segments that matched and predicted wrongly are
  not weakened; only segments that were right are reinforced.
- **Segment reuse over long runs.** A column that keeps bursting and never
  matches grows a new segment until it hits `max_segments_per_cell`, and then
  stops learning.
- **The spatial pooler's own learning.** Permanences there still never change.
