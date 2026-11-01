# Columns and cells

The vocabulary is four words deep. This repository implements the first two, and
that boundary explains most of what is missing.

| Word | What it is | In this repository |
| --- | --- | --- |
| input bit | one position in the encoded vector | `Array[Bool]`, via `ReadSeq[Bool]` |
| column | a unit that recognises something, and votes on it | `Column`, `ColumnView` |
| cell | one of several states a column can be in | not written |
| minicolumn | a column seen as the group of its cells | not written |

## A column here

A `Column` is a set of synapses and an overlap. Nothing else:

```pony
class Column
  embed synapses: Array[Synapse]
  fun overlap(active: ReadSeq[Bool], connection_threshold: F64): USize ?
```

Its identity is its index. Columns have no state that survives a round: the same
column with the same input always reports the same overlap. That is why a column
can be frozen into a `ColumnView` and shared between actor messages.

Nothing above a column exists either. The pooler holds a flat `Array[Column]` and
a `Grid` for the shape; the shape is used to decide who competes with whom, not to
group anything.

## A column in the reference implementations

The Go implementation this port follows has a second layer. From
`temporalMemoryConnections.go`:

```
func NewTemporalMemoryConnections(maxSynCount int, cellsPerColumn int, colDimensions []int) *TemporalMemoryConnections
func (tmc *TemporalMemoryConnections) CellsForColumn(column int) []int
func (tmc *TemporalMemoryConnections) ColumnForCell(cell int) int
```

A column is divided into `cellsPerColumn` cells. Each cell can be active or not,
so one column can express as many states as it has cells. `htm.core` defaults
that number to 32.

The advantage is context. A column with one state can only say "I recognise this".
A column with 32 cells can say "I recognise this, and I am in the third situation
where that happened". The temporal memory needs the second.

## Minicolumns

The word appears in HTM writing for the column-as-a-group-of-cells: same thing as
a column, seen from the cell side.

The implementations do not use it as a type:

- `htm.java` has no occurrence of `minicolumn` anywhere in its sources;
- `htm.core` mentions it in one message in `SPRegion.cpp`, and not at all in
  `TemporalMemory`;
- the Go implementation expresses the same idea through `cellsPerColumn` and
  `CellsForColumn`.

So a minicolumn type here would be a name with no behaviour behind it. When the
temporal memory is written, cells will arrive as the second index of a
column, which is the shape the reference code uses.

## What this means for the port

The spatial pooler is complete without cells. A cell has no meaning until
something needs to distinguish two situations in which the same column is active,
and that is the temporal memory's job.

[The temporal memory](temporal-memory.md) is where cells, segments and the state
they carry would enter.
