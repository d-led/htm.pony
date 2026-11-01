# Topology

The Go implementation keeps columns and inputs in one flat array and throws
their shape away. `Grid` keeps the shape: it maps flat indexes to coordinates
and answers which cells surround a given cell.

Two parts of the spatial pooler need the shape. A column's receptive field is
placed by spreading columns evenly across the input, and local inhibition
compares a column only with its neighbours.

## Building one

```pony
let grid = Grid([8; 8])?
grid.size  // 64
```

`Grid` is a value, so one instance can be handed to an actor. The constructor
raises when a dimension is missing or zero: a grid with no cells has no
topology to describe, and every later question about it would be meaningless.

Cells are laid out row-major. For `[3; 3]`, index `4` is the centre:

```pony
let grid = Grid([3; 3])?
grid.coords(4)?    // [1; 1]
grid.flatten([1; 1])?
```

Both directions are checked. `coords` raises past the end of the grid, and
`flatten` raises on the wrong number of coordinates or on a coordinate outside
its dimension.

## Neighbours

```pony
grid.neighbours(4, 1, false)  // the eight cells around the centre
```

`neighbours(flat, radius, wrap_around)` returns the cells within `radius` steps
in every dimension, as a set: each cell appears once and the cell itself is not
included. It raises when the index is outside the grid.

With `wrap_around` true the far edge of a dimension is adjacent to the near edge,
so a grid of hours in a day can compare 23:00 with 00:00. With it false the edge
cells simply have fewer neighbours, which is what a picture's border wants.

The result is unsorted. Callers that compare overlaps treat it as a set, so
order would only be a claim they do not make.

## Worked size

For an `[8; 8]` grid:

| Radius | Cells in one neighbourhood, including the cell | Neighbours returned |
| --- | --- | --- |
| 1 | 9 | 8 |
| 2 | 25 | 24 |

`Inhibition` counts the cell itself towards its own neighbourhood when it
decides how many columns of that neighbourhood may be active. This is why the
count it uses is one more than the list of neighbours: a lone column in a
corner still has room to be active.
