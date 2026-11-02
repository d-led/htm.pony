# Modules

Every file in the repository, with its types, its public members, and what state
it is in. Private members, those whose names begin with an underscore, are left
out.

This page is written by hand and says what each module is *for*. The
[API reference](api/index.md) is generated from the source and says exactly what
each type declares.

A member that can fail to produce a value is marked with `?`, which is how Pony
declares a partial function. A constructor marked `?` raises instead of
returning an object.

## The core package, `htm/`

### `topology.pony`

`Grid` — the shape of a grid of cells. A value, so it can be sent to an actor.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new val create(dims: Array[USize] val) ?` | raises when a dimension is missing or zero |
| `size` | `let size: USize` | how many cells the grid holds |
| `coords` | `fun box coords(flat: USize): Array[USize] ?` | flat index to coordinates |
| `flatten` | `fun box flatten(coords: ReadSeq[USize]): USize ?` | coordinates to flat index |
| `neighbours` | `fun box neighbours(flat: USize, radius: USize, wrap_around: Bool): Array[USize] ?` | the cells within `radius` steps, excluding the cell itself |

Tests: `test/topology_test.pony`.

### `dimensions.pony`

`Dimensions` — one function, `product(dims: ReadSeq[USize]): USize`, the number
of cells in a shape. The product of an empty list is 1, which is the identity
for the fold.

Tests: covered through `SpatialPoolerConfig`.

### `synapse.pony`

`Synapse` — one connection: which input, and the permanence the column holds for
it. A value.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new val create(input: USize, permanence: F64)` | |
| `input` | `let input: USize` | the index into the input |
| `permanence` | `let permanence: F64` | how strongly the column believes in it |
| `connected` | `fun connected(threshold: F64): Bool` | whether the permanence reaches the threshold |

Tests: exercised through `Column` and `Synapses`.

### `synapses.pony`

`Synapses` — overlap arithmetic that cannot fail. This is the version actors use,
because an actor constructor has no way to report a partial result.

| Member | Signature | What it does |
| --- | --- | --- |
| `overlap` | `fun overlap(synapses: ReadSeq[Synapse], active: ReadSeq[Bool], threshold: F64): USize` | active inputs seen by connected synapses, skipping any synapse outside the input |
| `fits` | `fun fits(synapses: ReadSeq[Synapse], width: USize): Bool` | whether every synapse reaches inside an input of this width |

### `column.pony`

`Column` — a reference object holding a set of synapses.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(synapses': ReadSeq[Synapse])` | copies the synapses in |
| `synapses` | `embed synapses: Array[Synapse]` | the connections |
| `overlap` | `fun overlap(active: ReadSeq[Bool], connection_threshold: F64): USize ?` | raises when a synapse reaches outside the input |

Tests: `test/column_test.pony`.

### `inhibition.pony`

`Inhibition` — which columns represent the input.

| Member | Signature | What it does |
| --- | --- | --- |
| `winners` | `fun winners(overlaps: ReadSeq[F64], count: USize): Array[USize] ?` | the `count` strongest columns, in ascending column order |
| `local` | `fun local(overlaps: ReadSeq[F64], grid: Grid box, radius: USize, density: F64): Array[USize] ?` | the columns that stand out among their neighbours |

Both refuse to let a column with overlap zero win.

Tests: `test/inhibition_test.pony`.

### `spatial_pooler_config.pony`

`SpatialPoolerConfig` — the shape and the competition settings. A value.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new val create(column_dimensions: Array[USize] val, input_dimensions: Array[USize] val, global_inhibition: Bool = false, num_active_columns_per_inh_area: F64 = 10.0, local_area_density: F64 = -1.0, potential_radius: USize = 16, potential_pct: F64 = 0.5, connection_threshold: F64 = 0.1, permanence_increment: F64 = 0.1, inhibition_radius: USize = 1)` | |
| `num_columns` | `fun num_columns(): USize` | cells in the column grid |
| `num_inputs` | `fun num_inputs(): USize` | cells in the input |
| `density` | `fun density(radius: USize): F64` | the share of an inhibition area that may stay active, capped at one half |

Tests: `test/spatial_pooler_config_test.pony`.

### `spatial_pooler.pony`

`Wiring` — deciding what a column looks at before anything has been learned.

| Member | Signature | What it does |
| --- | --- | --- |
| `synapses` | `fun synapses(config: SpatialPoolerConfig, input_grid: Grid, random: Rand, column: USize): Array[Synapse] ?` | a column's connections, drawn from one generator |
| `fresh_column` | `fun fresh_column(config: SpatialPoolerConfig, input_grid: Grid, random: Rand, index: USize): Column ?` | a wired column, raised until it can be heard and trimmed |
| `receptive_field` | `fun receptive_field(config: SpatialPoolerConfig, input_grid: Grid, column: USize): Array[USize]` | the inputs a column may reach |

`SpatialPooler` — the representation computation, in process.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(config: SpatialPoolerConfig, seed: U64 = 42) ?` | wires every column |
| `size` | `fun size(): USize` | how many columns |
| `compute` | `fun compute(input: ReadSeq[Bool]): Array[USize] ?` | the columns that represent the input |
| `columns` | `let columns: Array[Column]` | the wired columns |
| `config` | `let config: SpatialPoolerConfig` | the settings it was built with |

Tests: `test/spatial_pooler_test.pony`.

### `ballot_box.pony`

| Type | What it is |
| --- | --- |
| `Vote` (value) | one column's answer: `column` and `overlap` |
| `Ballot` (interface) | `be vote(Vote)` and `be cast(Array[Vote] iso)` — where votes go |
| `Tally` (interface) | `be tallied(Array[Vote] iso)` — where the tally goes |
| `BallotBox` (actor) | collects the votes on one question |
| `Deadline` (class) | the timer that closes a round when time runs out |

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(tally: Tally tag, expected: USize, quorum: USize = 0, deadline_ms: U64 = 0)` | a quorum of 0 or more than `expected` becomes `expected` |
| `vote` | `be vote(vote': Vote)` | adds one vote; ignored once the round is decided |
| `cast` | `be cast(votes: Array[Vote] iso)` | adds a whole shard's votes in one message |
| `deadline_reached` | `be deadline_reached()` | closes the round early |

Tests: `test/ballot_box_test.pony`.

### `column_shard.pony`

`ColumnWiring` (value) — one column's wiring as a value: `index`, its place in
the population, and the `synapses` it starts with.

`ColumnShard` (actor) — a band of columns sharing one actor.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(wirings: Array[ColumnWiring] val, config: SpatialPoolerConfig val)` | copies the synapses into columns of its own, and keeps the settings |
| `observe` | `be observe(active: Array[Bool] val, ballot: Ballot tag)` | pushes every column's overlap in one `cast` |
| `learn` | `be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val)` | adapts the named winners and raises the named starving columns, ignoring indices of other bands |

Tests: `test/column_shard_test.pony`.

### `pooler.pony`

| Type | What it is |
| --- | --- |
| `Representation` (interface) | `be represented(Array[USize] iso)` — whoever asked for a representation |
| `Round` (value) | one queued request: the input, whether the round learns, and who to answer |
| `Pooler` (actor) | the coordinator, and a `Tally` |
| `PoolerShards` (primitive) | bands of columns wired as `SpatialPooler` wires its own |

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(shards: Array[ColumnShard tag] val, grid: Grid val, config: SpatialPoolerConfig val)` | |
| `represent` | `be represent(active: Array[Bool] val, learn: Bool, asker: Representation tag)` | queues a round and starts it if nothing is in flight |
| `tallied` | `be tallied(votes: Array[Vote] iso)` | inhibits the votes, learns from the round if it was asked to, and answers the asker |
| `PoolerShards.build` | `fun build(config: SpatialPoolerConfig val, seed: U64, width: USize): Array[ColumnShard tag] val ?` | cuts the population into bands of `width` |

Tests: `test/pooler_test.pony`, `test/pooler_learning_test.pony`.

### `htm_types.pony`

`SetOk`, `SetFailed`, and `MatrixResult` — the result of writing to a matrix.

### `dense_binary_matrix.pony`

`DenseBinaryMatrix` — one `Bool` per cell.

| Member | Signature |
| --- | --- |
| `create` | `new create(width: USize, height: USize)` |
| `from_dense_2d_array` | `new from_dense_2d_array(rows: Array[Array[Bool]]) ?` |
| `set` | `fun ref set(row: USize, col: USize, value: Bool): MatrixResult` |
| `get` | `fun get(row: USize, col: USize): Bool` |
| `replace_row` | `fun ref replace_row(row: USize, values: Array[Bool]): MatrixResult` |
| `replace_row_by_indices` | `fun ref replace_row_by_indices(row: USize, indices: Array[USize]): MatrixResult` |
| `get_row_indices` | `fun get_row_indices(row: USize): Array[USize]` |
| `set_row_from_dense` | `fun ref set_row_from_dense(row: USize, values: Array[Bool]): MatrixResult` |
| `row_and_sum` | `fun row_and_sum(row_to_sum: ReadSeq[Bool]): Array[USize] ?` |

Tests: `test/dense_binary_matrix_test.pony`.

### `sparse_binary_matrix.pony`

`SparseEntry` (value) — the `row` and `col` of one set cell.

`SparseBinaryMatrix` — only the set cells are stored. Same members as the dense
matrix, with the same signatures.

Tests: `test/sparse_binary_matrix_test.pony`.

## The encoders, `htm/encoders/`

### `encoder_interfaces.pony`

`EncodingFailed` — the failure value. `SomeScalarEncoder` — the interface every
scalar encoder implements: `noop()`, `encode(input, learn_unused)`,
`encode_at_pos(input, learn_unused, output, pos)`.

### `scalar_encoder_params.pony`

`N`, `Radius`, `Resolution` and `ScalarOutputType` name which of the three sizes
was given. `ScalarEncoderParams` (value) carries `width`, `min_val`, `max_val`,
`periodic`, `output_type`, `range`, `resolution`, `name`, `radius`,
`clip_input`, `verbosity`, `n`.

### `scalar_encoder.pony`

`ScalarEncoder` — a contiguous block of set bits that slides with the value.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(params: ScalarEncoderParams val) ?` | raises on parameters that cannot describe an encoder |
| `encode` | `fun encode(input: F64, learn_unused: Bool): (Array[Bool] \| EncodingFailed)` | a new vector of `n` bits |
| `encode_at_pos` | `fun encode_at_pos(input: F64, learn_unused: Bool, output: Array[Bool] ref, pos: USize): (None \| EncodingFailed)` | writes into an existing vector |
| `decode` | `fun decode(encoded: Array[Bool]): Array[ScalarRange] ?` | the ranges an encoding covers |
| `n`, `radius`, `resolution`, `range`, `name` | `let ...` | the derived sizes; the width is `params.width` |
| `top_down_mapping` | `var top_down_mapping: (SparseBinaryMatrix \| None)` | bits to ranges, built on demand |

Warns, without failing, when `width` is below 21. That check is inherited from
the Go original.

Tests: `test/scalar_encoder_test.pony`.

### `scalar_range.pony`

`ScalarRange` (value) — `left` and `right`, with `eq`, `ne` and `string`.

### `date_encoder_params.pony`

`HolidayMonthDay` — a `(month, day)` pair. `DateEncoderParams` (value) carries
`holiday_width`, `holiday_radius`, `season_width`, `season_radius`,
`day_of_week_width`, `day_of_week_radius`, `weekend_width`, `weekend_radius`,
`time_of_day_width`, `time_of_day_radius`, `name`, `holidays`.

### `date_encoder.pony`

`DateEncoder` — five fields encoded into one vector.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(params: DateEncoderParams val) ?` | builds a scalar encoder per field and works out the offsets |
| `encode` | `fun encode(input: PosixDate, learn_unused: Bool = false): (Array[Bool] \| EncodingFailed)` | the vector |
| `width` | `let width: USize` | the total width, summed from the fields that are switched on |
| `season_offset`, `day_of_week_offset`, `weekend_offset`, `holiday_offset`, `time_of_day_offset` | `let ...` | where each field starts |

**Only the season field is written.** The other four encoders are constructed and
counted in `width`, but `encode` never calls them, so their bits stay `false`.
`_get_holiday_scalar` returns zero, with the intended calculation present as
commented Go code.

Tests: `test/date_encoder_test.pony` asserts the `PosixDate` fields and logs the
encoding; the comparison of the full vector is commented out.

### `noop_encoders.pony`

`NoOpScalarEncoder` — `noop()` is true, `encode_at_pos` writes nothing, and
`encode` returns `EncodingFailed` on purpose.

## Utilities, `htm/util/`

### `bool_array.pony`

`BadInput` — the failure value of the indexed helpers. `BoolArray` — conversions
and indexed operations on bit vectors: `from01`, `are_equal`, `subset_slice`,
`set_value_at_indices`, `set_value_in_range`, `on_indices`.

Tests: `test/array_conversions_test.pony`.

## Benchmarks, `microbenchmarks/`

`main.pony` registers one benchmark, and the benchmark's `apply` calls
`DoNotOptimise.observe()` and nothing else. **The benchmarks measure nothing
yet.** The Go repository has a benchmark for the dense matrix that has not been
ported.
