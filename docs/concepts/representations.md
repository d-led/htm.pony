# Representations

A representation here is a bit vector: `Array[Bool]` for a value that is written,
`ReadSeq[Bool]` for one that is read. HTM calls it a sparse distributed
representation (SDR) when few of its bits are set and each bit carries meaning
on its own.

Sparsity is what makes the rest of the pipeline work. The spatial pooler turns a
64-bit input into a few dozen of 64 columns; the inhibition stage then keeps only
the strongest of those. Two inputs that share active bits produce representations
that share active columns.

## Bit vectors

`Array[Bool]` is the form every stage takes and produces. There is no packed bit
type in this repository: a bit costs a byte, and the code that reads these
vectors says `ReadSeq[Bool]` so a caller can pass any array.

`BoolArray` in `htm/util/bool_array.pony` holds the conversions and indexed
operations that would otherwise be rewritten at each call site:

| Function | What it does |
| --- | --- |
| `from01(Array[U8])` | turns `0`/`1` bytes into a bit vector |
| `are_equal(a, b)` | compares two vectors of the same width |
| `subset_slice(values, indices)` | picks positions, or returns `BadInput` |
| `set_value_at_indices(values, indices, value)` | sets named positions |
| `set_value_in_range(values, value, start, length)` | sets a contiguous run |
| `on_indices(values)` | the positions that are set |

The indexes are checked. `subset_slice` and the setters return `BadInput`
instead of raising, because the callers that use them are loops that have to
report a position rather than an exception.

## Matrices

A matrix is the two-dimensional form: one row per item, one column per bit.
Two implementations share the same method names, so code can be written against
either.

| | `DenseBinaryMatrix` | `SparseBinaryMatrix` |
| --- | --- | --- |
| Holds | `Array[Bool]`, one entry per cell | `Array[SparseEntry]`, only set cells |
| Memory | width × height | proportional to the bits that are set |
| `set` on a set cell | overwrites | keeps one entry |
| `set` to `false` | writes `false` | removes the entry |

Both offer `set`, `get`, `replace_row`, `replace_row_by_indices`,
`get_row_indices`, `set_row_from_dense`, `row_and_sum`, and construction from a
dense two-dimensional array.

`set` returns `MatrixResult`, which is `SetOk` or `SetFailed`. Out-of-range
coordinates fail rather than being clamped, so a wrong index is visible at the
call that made it.

```pony
let matrix = SparseBinaryMatrix(4, 2)
matrix.set(0, 1, true)
matrix.set(0, 3, true)

matrix.get_row_indices(0)          // [1; 3]
matrix.row_and_sum(active_vector)? // one count per row
```

`row_and_sum` takes a vector exactly as wide as the matrix and returns one
number per row: how many of that row's set entries are also set in the input. A
vector of the wrong width is an error rather than a partial sum, because a
shorter one would leave part of each row unread and report a quiet zero.

## What is not here

There is no rolling SDR, no union or intersection primitive, and no compressed
bit representation. A caller that wants to combine two representations writes
the loop, or uses `BoolArray`.
