# Temporal memory

!!! warning "Not implemented"

    Nothing on this page exists in this repository. It describes what the
    temporal memory is and where it would attach, so that the gap between the
    spatial pooler and a working HTM is stated rather than implied.

The spatial pooler answers "what is this input". The temporal memory answers
"what usually comes next". It takes the active columns of one step, compares them
with what it remembers about the previous steps, and predicts which columns will
be active at the next one.

## Why it needs cells

A column is either active or not, so it cannot distinguish two situations in
which it is active. Sequence learning needs exactly that distinction: the same
column fires in many contexts, and what follows differs between them.

That is what [cells](columns-and-cells.md) are for. A column holds several cells,
and which of them is active records the context. The references express this with
`cellsPerColumn`, which `htm.core` defaults to 32.

## The mechanism, in the reference

The Go implementation has the pieces under names that say what they do. The entry
point takes the spatial pooler's output:

```
func (tm *TemporalMemory) Compute(activeColumns []int, learn bool)
```

Inside, the steps are:

| Step | Function | What it does |
| --- | --- | --- |
| 1 | `computeActiveSynapses` | finds which cells were active at the previous step |
| 2 | `computePredictiveCells` | a segment predicts when enough of its synapses are on active cells |
| 3 | `activateCorrectlyPredictiveCells` | cells that predicted correctly become active |
| 4 | `burstColumns` | a column that was not predicted activates all its cells |
| 5 | `learnOnSegments` | segments that predicted get reinforced, the others weakened |
| 6 | `getBestMatchingCell` | picks the cell to extend when a column bursts |

The structures those steps work on are in `temporalMemoryConnections.go`:

```
CreateSegment(cell) int
CreateSynapse(segment, sourceCell int, permanence float64) *TmSynapse
SegmentsForCell(cell int) []int
UpdateSynapsePermanence(synapse int, permanence float64)
```

A **segment** belongs to one cell and holds synapses onto other cells. A segment
is predictive when enough of those synapses reach cells that are currently
active. Learning moves permanences, which is the same operation the spatial
pooler needs and does not yet have.

The Go repository carries a second, older implementation as well:
`segment.go`, `segmentUpdate.go`, `temporalPooler.go` and `trivialPredictor.go`.

## Where it would attach here

The pooler already emits the right thing. `Pooler` answers with
`Array[USize] iso`, the active columns, and `Representation.represented` is where
they arrive.

So a temporal memory would sit behind `Representation`, take the column indexes it
is given, and hold the state that the pooler deliberately does not have. The
pooler stays a stateless mapper from input to columns; the sequence layer keeps
the history.

## What is missing, concretely

- **Cells.** No type, no `cellsPerColumn`, no cell index. See
  [columns and cells](columns-and-cells.md).
- **Segments and distal synapses.** `Synapse` here reaches an input bit, not
  another cell.
- **Activation state that survives a step.** Every type in `htm/` is either a
  value or a stateless actor. A round leaves no trace.
- **A previous step.** Nothing in the code holds "the cells that were active
  before".
- **Permanence learning.** The temporal memory cannot work without it, and neither
  can a spatial pooler that adapts. `adaptSynapses`, `updateDutyCycles` and
  `updateBoostFactors` from the Go implementation are all absent.

The first of these is the one to build first: learning. It needs no new types, it
makes the spatial pooler complete, and the temporal memory depends on it.
