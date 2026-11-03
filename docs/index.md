# HTM.Pony

Hierarchical Temporal Memory in Pony. A port of
[htm-community/htm](https://github.com/htm-community/htm) (MIT), with the
computation arranged as actors. Which file came from where, and under which
licence, is written down in [Sources](sources.md).

HTM models a stream of inputs as sparse distributed representations and learns
what tends to follow what. This port has both sides: encoders turn values into
bit vectors, and a spatial pooler turns a bit vector into a sparse set of columns
that recognise it. The temporal memory then learns which cells in those columns
predict the next input, the CLA temporal pooler learns the situations those
predictions belong to and can say several steps ahead, and the classifiers turn
predictions into probabilities over categories.

## Status

| Area | State |
| --- | --- |
| Dense and sparse binary matrices | Implemented, tested |
| Grid topology: coordinates, flattening, neighbours | Implemented, tested |
| Scalar encoder, including top-down mapping | Implemented, tested |
| Date encoder | Implemented, tested: season, day of week, weekend, time of day and holidays |
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
| Anomaly score on the actor path | Implemented, tested |
| Category encoder | Implemented, tested |
| Fixed-width category encoder, open set | Implemented, tested |
| Random distributed encoder | Implemented, tested |
| Grid cell encoder: a place becomes periodic receptive fields | Implemented, tested |
| SimHash document encoder: a document becomes the positions its words vote for | Implemented, tested |
| A graph as one SDR | Implemented, tested - `GraphEncoder` |
| CLA temporal pooler: pooling, backtracking, a forecast | Implemented, tested |
| The pooler on actors | Implemented, tested |
| Retries with a growing deadline, in both coordinators | Implemented, tested |

The [module reference](reference/modules.md) lists every file, type and public
function. Concept pages describe the ideas underneath:
[columns and cells](concepts/columns-and-cells.md),
[temporal memory](concepts/temporal-memory.md) and
[temporal pooler](concepts/temporal-pooler.md).

The [roadmap](roadmap.md) says what this is for, in the order the goals were set -
predictions, classification, online anomaly detection. What was left of the
algorithm is now in: the CLA temporal pooler was the last piece, and the
[handoff](handoff.md) is the working page for whoever picks this up next - what
was decided deliberately, which parts of the reference were not ported, and the
traps.

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
| `htm/retry.pony` | `Retry`: how long a retry waits, shared by both coordinators |
| `htm/dense_binary_matrix.pony` | `DenseBinaryMatrix`: one bit per cell |
| `htm/sparse_binary_matrix.pony` | `SparseBinaryMatrix`: only the set cells |
| `htm/htm_types.pony` | `MatrixResult`: `SetOk` or `SetFailed` |
| `htm/temporal_memory_params.pony` | `TemporalMemoryParams`: columns, cells, thresholds |
| `htm/temporal_synapse.pony`, `htm/temporal_segment.pony` | a cell's memory of what came before |
| `htm/temporal_column.pony` | `TemporalColumn`: one column's cells, and its step |
| `htm/temporal_memory.pony` | `TemporalMemory`: the sequence memory in one process |
| `htm/temporal_output.pony` | `TemporalOutput`: one step as a value |
| `htm/temporal_shard.pony` | `TemporalBand`, `TemporalSink`, `TemporalColumnShard`: a band of columns as actors |
| `htm/temporal_region.pony` | `TemporalRegion`, `TemporalBallot`: the memory on actors |
| `htm/temporal_pooler_config.pony` | `TemporalPoolerConfig`: the pooler's shape |
| `htm/cla_segment.pony`, `htm/cla_cell.pony`, `htm/cla_state.pony` | the pooler's cells, their segments, and what is active and predicted |
| `htm/cla_segment_update.pony` | `ClaSegmentUpdate`: a proposal, waiting to be judged by the next step |
| `htm/cla_output.pony` | `ClaOutput`: one pooler step as a value |
| `htm/temporal_pooler.pony` | `TemporalPooler`: the CLA pooler in one process |
| `htm/temporal_pooler_actor.pony` | `TemporalPoolerActor`, `ClaObserver`: the pooler on actors |
| `htm/sdr_merger.pony` | `SDRMerger`: two representations into one, and cutting one down |
| `htm/sdr_classifier.pony`, `htm/prediction_classifier.pony` | predictions as probabilities over categories |
| `htm/streaming_anomaly_detector.pony`, `htm/anomaly_likelihood.pony` | the anomaly score, and how ordinary it is |
| `htm/anomaly_stream.pony` | the two of them on the actor path |
| `htm/encoders/` | `ScalarEncoder`, `DateEncoder`, `CategoryEncoder`, `SDRCategoryEncoder`, `GridCellEncoder`, `SimHashDocumentEncoder`, `GraphEncoder`, images, and their parameters |
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
