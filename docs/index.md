# HTM.Pony

Hierarchical Temporal Memory in Pony. A port of
[htm-community/htm](https://github.com/htm-community/htm) (MIT), with the
computation arranged as actors.

HTM models a stream of inputs as sparse distributed representations and learns
what tends to follow what. This port has both sides: encoders turn values into
bit vectors, and a spatial pooler turns a bit vector into a sparse set of columns
that recognise it. The temporal memory then learns which cells in those columns
predict the next input, and the classifiers turn predictions into probabilities
over categories.

## Status

| Area | State |
| --- | --- |
| Dense and sparse binary matrices | Implemented, tested |
| Grid topology: coordinates, flattening, neighbours | Implemented, tested |
| Scalar encoder, including top-down mapping | Implemented, tested |
| Date encoder | Season encoded; four further fields reserve width but are not written |
| Column wiring, overlap, global and local inhibition | Implemented, tested |
| Spatial pooler, in process | Implemented, tested |
| Actor layer: shards, ballot box, pooler | Implemented, tested |
| Image fingerprint and encoder, from pixels | Implemented, tested |
| A picture file decoder (PNG, JPEG, BMP, GIF) | Implemented, tested |
| Permanence learning, duty cycles, boosting | Implemented, tested, in process and on actors |
| Temporal memory: cells, segments, prediction, bursts | Implemented, tested |
| Temporal memory on actors | Implemented, tested |
| SDR classifier, categories | Implemented, tested |
| Prediction classifier: the label of the next step | Implemented, tested |
| Streaming anomaly score, and its likelihood | Implemented, tested |
| Category encoder | Implemented, tested |
| Random distributed encoder | Implemented, tested |
| Graph encoder | Not written |

The [module reference](reference/modules.md) lists every file, type and public
function, including the parts that do nothing yet. Two concept pages describe what
is missing and why it matters: [columns and cells](concepts/columns-and-cells.md)
and [temporal memory](concepts/temporal-memory.md).

## How the computation is arranged

The spatial pooler runs in one process or on actors. Both paths compute the same
representation from the same seed, and both learn from the same rounds; the
[actor example](examples.md#the-same-computation-on-actors) checks that they
agree round by round through a learning session.

The in-process path is a plain object graph:

```
input bits -> column overlaps -> inhibition -> representation
```

The actor path keeps that computation and changes where it runs:

```text
Asker        --represent(active, learn, asker)-->  Pooler
Pooler       --observe(active, ballot)-->          ColumnShard, once per shard
ColumnShard  --cast(votes)-->                      BallotBox
BallotBox    --tallied(votes)-->                   Pooler
Pooler       --learn(active, winners, starving)--> ColumnShard, once per shard
Pooler       --represented(winners)-->             Asker
```

Nothing in that path returns a value. Each actor pushes to the next and the
answer arrives as a message, which is what lets a round overlap with work that
is still in flight.

## The modules

| Module | What it holds |
| --- | --- |
| `htm/topology.pony` | `Grid`: flat index to coordinates, and the neighbours of a cell |
| `htm/synapse.pony` | `Synapse`: one input, and the permanence the column holds for it |
| `htm/synapses.pony` | `Synapses`: overlap counting that cannot fail |
| `htm/column.pony` | `Column`: a set of synapses and its overlap |
| `htm/inhibition.pony` | `Inhibition`: which columns win, globally or among neighbours |
| `htm/dimensions.pony` | `Dimensions`: the product of a shape |
| `htm/spatial_pooler_config.pony` | `SpatialPoolerConfig`: the shape, and how strictly columns compete |
| `htm/spatial_pooler.pony` | `Wiring` and `SpatialPooler`: receptive fields, and compute |
| `htm/ballot_box.pony` | `Vote`, `Ballot`, `Tally`, `BallotBox`, `Deadline`: one round of votes |
| `htm/column_shard.pony` | `ColumnWiring`, `ColumnShard`: a band of columns sharing one actor |
| `htm/pooler.pony` | `Representation`, `Shard`, `Round`, `Pooler`: the coordinator |
| `htm/dense_binary_matrix.pony` | `DenseBinaryMatrix`: one bit per cell |
| `htm/sparse_binary_matrix.pony` | `SparseBinaryMatrix`: only the set cells |
| `htm/htm_types.pony` | `MatrixResult`: `SetOk` or `SetFailed` |
| `htm/encoders/` | `ScalarEncoder`, `DateEncoder` and their parameters |
| `htm/util/bool_array.pony` | `BoolArray`: conversions and indexed access on bit vectors |

## Requirements

Pony 0.77 or later, with corral. Both are installed by
[ponyup](https://github.com/ponylang/ponyup).

## Building

```
cd test
corral run -- ponyc --debug
./test
```

The examples build the same way from their own directories. See
[getting started](getting-started.md) for the whole sequence, including the
first run of each example.

## References

- [htm-community/htm](https://github.com/htm-community/htm) — the Go
  implementation this port follows
- [Numenta](https://numenta.org/) — HTM and Sparse Distributed Representations
