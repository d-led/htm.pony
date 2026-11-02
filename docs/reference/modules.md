# Modules

Every file in the repository and what it is for; where a test file exercises it,
the section names that file. Where a type's surface is worth naming here as well
- because the meanings of its fields are what a reader has to get right - a table
follows.

This page is written by hand and says what each module is *for*. The
[API reference](api/index.md) is generated from the source and lists every
declared member of every type, so it is the one to trust for a signature.

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

Tests: covered through `test/column_test.pony`.

### `column.pony`

`Column` — a reference object holding a set of synapses.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(synapses': ReadSeq[Synapse])` | copies the synapses in |
| `synapses` | `embed synapses: Array[Synapse]` | the connections |
| `overlap` | `fun overlap(active: ReadSeq[Bool], connection_threshold: F64): USize ?` | raises when a synapse reaches outside the input |
| `adapt` | `fun ref adapt(active: ReadSeq[Bool], strengthen_by: F64, weaken_by: F64)` | moves every permanence towards the input it sees, or away from it |
| `ensure_connected` | `fun ref ensure_connected(stimulus_threshold: USize, connection_threshold: F64, stride: F64)` | raises the whole receptive field until enough synapses are connected |
| `strengthen_all` | `fun ref strengthen_all(by: F64)` | raises every permanence, staying inside 0 and 1 |
| `trim` | `fun ref trim(below: F64)` | lets go of the connections weaker than `below`, keeping the synapse at zero |

Tests: `test/column_test.pony`.

### `inhibition.pony`

`Inhibition` — which columns represent the input.

| Member | Signature | What it does |
| --- | --- | --- |
| `winners` | `fun winners(overlaps: ReadSeq[F64], count: USize): Array[USize] ?` | the `count` strongest columns, in ascending column order |
| `local` | `fun local(overlaps: ReadSeq[F64], grid: Grid box, radius: USize, density: F64): Array[USize] ?` | the columns that stand out among their neighbours |

Both refuse to let a column with overlap zero win.

Tests: `test/inhibition_test.pony`.

### `tie_breaker.pony`

`TieBreaker` — the little fixed noise per column that keeps exact ties from
always going to the lowest index.

| Member | Signature | What it does |
| --- | --- | --- |
| `of` | `fun of(columns: USize, seed: U64): Array[F64] val` | one value per column, each in `[0, 0.01)`; the generator is warmed up first, because a freshly seeded one gives values that track the seed |
| `nudged` | `fun nudged(claims: Array[F64], noise: Array[F64] val): Array[F64] ?` | the claims to compete with — a copy, each real claim plus its own nudge, and a claim of nothing left alone |

Both pools draw it from their seed before inhibiting, so the two paths agree
when they are seeded alike.

Tests: `test/tie_breaker_test.pony`, and the tie itself through
`test/pooler_test.pony`.

### `spatial_pooler_config.pony`

`SpatialPoolerConfig` — the shape and the competition settings. A value.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new val create(column_dimensions: Array[USize] val, input_dimensions: Array[USize] val, global_inhibition: Bool = false, num_active_columns_per_inh_area: F64 = 10.0, local_area_density: F64 = -1.0, potential_radius: USize = 16, potential_pct: F64 = 0.5, connection_threshold: F64 = 0.1, permanence_increment: F64 = 0.1, inhibition_radius: USize = 1, permanence_decrement: F64 = 0.01, stimulus_threshold: USize = 0, duty_cycle_period: USize = 1000, max_boost: F64 = 10.0, min_overlap_duty_cycle: F64 = 0.001, min_active_duty_cycle: F64 = 0.001)` | |
| `num_columns` | `fun num_columns(): USize` | cells in the column grid |
| `num_inputs` | `fun num_inputs(): USize` | cells in the input |
| `density` | `fun density(radius: USize): F64` | the share of an inhibition area that may stay active, capped at one half |
| `trim_threshold` | `fun trim_threshold(): F64` | the permanence below which a connection is let go of |
| `raise_stride` | `fun raise_stride(): F64` | how much a column raises its permanences when it cannot be heard |

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
| `compute` | `fun ref compute(input: ReadSeq[Bool], learn: Bool = false): Array[USize] ?` | the columns that represent the input, and with `learn` the change that input makes |
| `boost_factor` | `fun box boost_factor(column: USize): F64 ?` | how much the column's claim is multiplied by while learning |
| `columns` | `let columns: Array[Column]` | the wired columns |
| `config` | `let config: SpatialPoolerConfig` | the settings it was built with |

Tests: `test/spatial_pooler_test.pony`; `Wiring` through
`test/wiring_test.pony` (which is where the reference's `mapPotential` and
`initPermanence` cases live), and what a learning round changes through
`test/spatial_pooler_learning_test.pony`.

### `ballot_box.pony`

| Type | What it is |
| --- | --- |
| `Vote` (value) | one column's answer: `column` and `overlap` |
| `Ballot` (interface) | `be vote(Vote)` and `be cast(USize, Array[Vote] iso)` — where votes go, the second naming the band they came from |
| `Tally` (interface) | `be tallied(Array[Vote] iso, Array[USize] val)` — where the tally goes, with the bands that never reported |
| `BallotBox` (actor) | collects the votes on one question |
| `Deadline` (class) | the timer that closes a round when time runs out |

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(tally: Tally tag, expected: USize, quorum: USize = 0, deadline_ms: U64 = 0, bands: Array[USize] val = [])` | a quorum of 0 or more than `expected` becomes `expected`; the roster is what lets the box name a silent band |
| `vote` | `be vote(vote': Vote)` | adds one vote; ignored once the round is decided |
| `cast` | `be cast(band: USize, votes: Array[Vote] iso)` | adds a whole band's votes in one message, and notes that the band reported |
| `deadline_reached` | `be deadline_reached()` | closes the round early |

Tests: `test/ballot_box_test.pony`.

### `column_shard.pony`

`ColumnWiring` (value) — one column's wiring as a value: `index`, its place in
the population, and the `synapses` it starts with.

`ColumnShard` (actor) — a band of columns sharing one actor.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(wirings: Array[ColumnWiring] val, config: SpatialPoolerConfig val)` | copies the synapses into columns of its own, and keeps the settings |
| `observe` | `be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag)` | pushes every column's overlap in one `cast`, naming its own band |
| `learn` | `be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val)` | adapts the named winners and raises the named starving columns, ignoring indices of other bands |

Tests: `test/column_shard_test.pony`.

### `pooler.pony`

| Type | What it is |
| --- | --- |
| `Representation` (interface) | `be represented(Array[USize] iso, USize)` — whoever asked for a representation, and how many columns the round never heard from |
| `Shard` (interface) | `be observe(USize, Array[Bool] val, Ballot tag)` and `be learn(Array[Bool] val, Array[USize] val, Array[USize] val)` — what the pooler asks of a band of columns; the number is the band's own name, echoed back with the votes so a silent band can be asked again |
| `Round` (value) | one queued request: the input, whether the round learns, and who to answer |
| `Pooler` (actor) | the coordinator, and a `Tally` |
| `PoolerShards` (primitive) | bands of columns wired as `SpatialPooler` wires its own |

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(shards: Array[Shard tag] val, grid: Grid val, config: SpatialPoolerConfig val, deadline_ms: U64 = 0, seed: U64 = 42)` | a deadline of 0 means the round waits for every shard; with one, a round that closed with bands missing asks those once more. The seed is what `TieBreaker` is drawn from, and must match the in-process pooler's for the two paths to agree |
| `represent` | `be represent(active: Array[Bool] val, learn: Bool, asker: Representation tag)` | queues a round and starts it if nothing is in flight |
| `reconfigure` | `be reconfigure(shards: Array[Shard tag] val)` | hand over the bands to ask from the next round on; the round in flight keeps the bands it was asked of |
| `tallied` | `be tallied(votes: Array[Vote] iso, silent: Array[USize] val)` | asks the silent bands again if the round may be retried, otherwise inhibits the votes, learns from the round if it was asked to, and answers the asker |
| `PoolerShards.build` | `fun build(config: SpatialPoolerConfig val, seed: U64, width: USize): Array[Shard tag] val ?` | cuts the population into bands of `width` |

Tests: `test/pooler_test.pony`, `test/pooler_learning_test.pony`.

### `htm_types.pony`

`SetOk`, `SetFailed`, and `MatrixResult` — the result of writing to a matrix.

Tests: covered through the two matrix test files.

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

### `column_learning.pony`

`ColumnLearning` - what a pooler remembers about how its columns have been doing:
two moving averages per column, which columns are starving, and how hard to push
them. None of it touches a column's synapses. It decides, and the driver does.

Tests: `test/column_learning_test.pony`.

### `streaming_anomaly_detector.pony`

`StreamingAnomalyDetector` - one input in, one anomaly score out: the pooler turns
the input into columns, the memory learns the order they arrive in, and the score
is the share of this step's columns the memory did not expect. Learning and
scoring happen in the same pass, so there is no training phase and no frozen
model.

Tests: `test/anomaly_test.pony`.

### `anomaly_likelihood.pony`

`AnomalyLikelihood` - a raw anomaly score read against the scores that came
before it, as a probability. A score of 0.5 means nothing on its own; what the
likelihood adds is whether that is ordinary for this stream.

Tests: `test/anomaly_likelihood_test.pony`.

### `normal.pony`

`Normal` - the distribution the likelihood fits to a window of scores: a mean and
a spread taken from samples, and the probability of seeing a value at least this
far out.

Tests: covered through `AnomalyLikelihood`.

### `sdr_classifier.pony`

`SDRClassifier` - probabilities over categories for a sparse set of active bits,
learned one step at a time.

Tests: `test/sdr_classifier_test.pony`.

### `prediction_classifier.pony`

`PredictionClassifier` - the label of the next step, learned from what a memory
predicted and what then happened.

Tests: `test/prediction_classifier_test.pony`.

### `temporal_memory_params.pony`

`TemporalMemoryParams` - the shape of a temporal memory and how strictly it
predicts: columns, cells per column, the activation and connection thresholds,
the permanence steps, and the two limits that stop a cell growing without bound.

Tests: covered through `test/temporal_memory_test.pony`.

### `temporal_synapse.pony`

`TemporalSynapse` - one cell's connection to another, and the permanence that
decides whether the connection counts.

Tests: covered through `test/temporal_memory_test.pony`.

### `temporal_segment.pony`

`TemporalSegment` - the set of cells whose activity makes a segment predict. It
matches the previous step, moves towards or away from it, takes new cells when it
is too small to fire, and drops the connections that stopped mattering.

Tests: covered through `test/temporal_memory_test.pony`.

### `temporal_column.pony`

`ColumnStep` (value) - which of a column's cells a step activated, and whether the
column had to burst.

`TemporalColumn` - one column's own segments, and the three things a step asks of
it: which cells it has, which cells it predicts, and what it does with the
columns that are active now.

Tests: covered through `test/temporal_memory_test.pony`.

### `temporal_memory.pony`

`TemporalMemory` - the in-process driver over a population of `TemporalColumn`s.
One step in, one `TemporalOutput` out.

Tests: `test/temporal_memory_test.pony`.

### `temporal_output.pony`

`TemporalOutput` (value) - what one step produced: the cells that fired, the cells
it expects next, and the columns that burst. The derived forms -
`active_columns`, `predicted_columns` and `anomaly` - are what a caller usually
wants, since a cell number means little without the shape to read it against.

Tests: covered through `TemporalMemory`.

### `temporal_shard.pony`

`TemporalSink` (interface) - where a shard reports.

`TemporalColumnShard` (actor) - a band of temporal columns that share one actor.
It answers twice per round, and has to: a prediction is about a state that
includes what every column did.

Tests: covered through `TemporalRegion`.

### `temporal_region.pony`

`TemporalObserver` (interface) - whoever asked a region for a step.

`TemporalRequest` (value) - one step waiting to be run.

`TemporalRegion` (actor) - temporal memory arranged as actors. A round is two
passes over the shards, activate then predict, and the asker hears back only when
both are in.

`TemporalShards` (primitive) - cutting a population into bands of a given width.

Tests: `test/temporal_region_test.pony`.

## The encoders, `htm/encoders/`

### `encoder_interfaces.pony`

`EncodingFailed` — the failure value. `SomeScalarEncoder` — the interface every
scalar encoder implements: `noop()`, `encode(input, learn_unused)`,
`encode_at_pos(input, learn_unused, output, pos)`.

Tests: covered through the encoders that implement it.

### `scalar_encoder_params.pony`

`N`, `Radius`, `Resolution` and `ScalarOutputType` name which of the three sizes
was given. `ScalarEncoderParams` (value) carries `width`, `min_val`, `max_val`,
`periodic`, `output_type`, `range`, `resolution`, `name`, `radius`,
`clip_input`, `verbosity`, `n`.

Tests: `test/scalar_encoder_test.pony`.

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

Tests: `test/scalar_encoder_test.pony`.

### `date_encoder_params.pony`

`HolidayMonthDay` — a `(month, day)` pair. `DateEncoderParams` (value) carries
`holiday_width`, `holiday_radius`, `season_width`, `season_radius`,
`day_of_week_width`, `day_of_week_radius`, `weekend_width`, `weekend_radius`,
`time_of_day_width`, `time_of_day_radius`, `name`, `holidays`.

Tests: `test/date_encoder_test.pony`.

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

### `category_encoder.pony`

`CategoryEncoder` (value) - one block of bits per label, with no overlap between
labels, and the block read back to the label it came from.

Tests: `test/category_encoder_test.pony`.

### `random_distributed_scalar.pony`

`RandomDistributedScalarEncoder` - a real number into a random-looking set of
bits whose overlap carries the distance, without a range having to be known first.
The bits come from this library's generator, so an encoding is reproducible here
and nowhere else.

Tests: `test/random_distributed_scalar_test.pony`.

### `grayscale_image.pony`

`GrayscaleImage` (value) - the picture both image steps work on: width, height,
and one brightness per pixel.

Tests: covered through `test/image_encoder_test.pony`.

### `image_decoder.pony`

`ImageDecoder` (interface) and `DecodeFailed` - what a file decoder must provide,
so that the encoder never learns a file format.

Tests: covered through `test/stb_decoder_test.pony`.

### `image_encoder_params.pony`

`ImageEncoderParams` (value) - the shape of an image representation: how many
positions it has, how many bits the fingerprint has, and the seed that decides
which positions each bit owns.

Tests: `test/image_encoder_test.pony`.

### `difference_hash.pony`

`DifferenceHash` - a picture's fingerprint: which neighbouring pixels are
brighter than which, which is why scale and brightness leave it unchanged.

Tests: covered through `test/stb_decoder_test.pony`.

### `image_fingerprint.pony`

`ImageFingerprint` (value) - a picture reduced to one bit per comparison, in a
fixed order, ready to be encoded. The size is not fixed: difference hashing gives
64 bits and a stronger hash can give more.

Tests: `test/image_encoder_test.pony`.

### `image_encoder.pony`

`ImageEncoder` (value) — a picture, or a fingerprint of one, into a
representation. It is a value rather than a reference so that one can be built
once and handed to an actor; the positions it draws are its whole state and
nothing moves them.

Tests: `test/image_encoder_test.pony`.

### `picture_encoder.pony`

`PictureSink` (interface) and `PictureEncoder` (actor) — the picture pipeline as
an actor: bytes in one message, and either a fingerprint with the bits it makes,
or a refusal, in another.

| Member | Signature | What it does |
| --- | --- | --- |
| `create` | `new create(encoder: ImageEncoder val)` | takes an encoder already drawn, because an actor constructor cannot fail and `ImageEncoder` can |
| `picture` | `be picture(bytes: Array[U8] val, asker: PictureSink tag)` | decodes, fingerprints and encodes one picture, then answers |

One of these is the minimum; more of them is a fan-out over pictures in flight.
They are not sized to scheduler threads — Pony multiplexes many actors onto a
thread — but each one that is inside `stb_image` occupies a thread while it is
in there, so N at once needs N threads to run on.

Tests: `test/picture_encoder_test.pony`.

### `stb/stb_decoder.pony`

`StbDecoder` (primitive) - an `ImageDecoder` over [stb_image](https://github.com/nothings/stb),
which reads PNG, JPEG, BMP and GIF. It is the one place a file format is named,
and the one call in this library that is not Pony.

`stbi_load_from_memory` decodes inside C, on the thread that called it, and
cannot be interrupted or abandoned, so the size is decided before it starts:
`stbi_info_from_memory` reads the header, and a picture above `pixel_limit`
(4096 by 4096, sixteen megabytes of brightness) is refused with `DecodeFailed`
without a byte being allocated for it. A file of a few hundred bytes can name a
picture of any size at all — that is the shape of the attack this turns aside —
and the limit is where this library says what it is willing to make. Below it,
everything the file asks for is stb's business, and the deadline a caller gives a
pooler is what stands on the other side.

Tests: `test/stb_decoder_test.pony`.

## Utilities, `htm/util/`

### `bool_array.pony`

`BadInput` — the failure value of the indexed helpers. `BoolArray` — conversions
and indexed operations on bit vectors: `from01`, `are_equal`, `subset_slice`,
`set_value_at_indices`, `set_value_in_range`, `on_indices`.

Tests: `test/array_conversions_test.pony`.

### `erfc.pony`

`Erfc` — the complementary error function, `1 - erf(x)`: the share of a normal
curve further than `x` standard deviations from its middle. `of(x)` is the
Numerical Recipes approximation, so there is no dependency and no link to a
maths library, at an absolute error below 1.2e-7. `Normal.tail_probability` is
its only caller: it is what turns a distance from the mean into a probability.

Tests: covered through `test/anomaly_likelihood_test.pony`, which holds it to
known values at four points.

## Benchmarks, `microbenchmarks/`

`main.pony` measures `row_and_sum` twice over one matrix shape - two thousand rows
of two hundred and fifty-six columns, one cell in fifty filled - once on
`DenseBinaryMatrix` and once on `SparseBinaryMatrix` holding the same cells. The
dense matrix walks every cell and the sparse one walks only the cells that are
set, so the ratio between the two numbers is what the density does to that
operation. Both matrices are built in the benchmark's constructor, so building
one is not inside the measurement.

Run them with `cd microbenchmarks && corral run -- ponyc && ./microbenchmarks`.
`pony_bench` reports the mean and the median per operation and adjusts both for
its own overhead.
