# Where the code comes from

Every file here is either a translation of a file in another repository or this
repository's own work, and this page says which. It exists for two reasons: a
licence is a promise about where code came from, and a reader who wants to check
the port against its original needs to know where the original is.

The rule the files follow is the same one this page states: a file that is a
translation says so at the top, with the upstream file's name, and a file that
is not says nothing extra. Where a file was written from another library's
*description* rather than its source, it says that too, because the difference
matters.

## The upstreams, and what may be done with each

| upstream | licence | what this repository does with it |
| --- | --- | --- |
| [`htm-community/htm`](https://github.com/htm-community/htm) - the Go reference, Copyright 2014 Zac Gross | MIT | **The porting source.** Files may be translated line for line. |
| [`htm.core`](https://github.com/htm-community/htm.core) | AGPL-3.0 | **Read, never transcribed.** Algorithms are written from its account of them; its golden-bits tests are not ported, because they pin a random stream rather than the encoding. |
| `htm.java`, `nupic`, `nupic.core` | MIT / AGPL mix per repository | Read to see what the modern implementations do, and cited where a design chose between them. |
| [stb_image](https://github.com/nothings/stb) v2.30 (vendored in `htm/encoders/stb/`) | public domain / MIT | Used as the picture decoder, unmodified, as a C shim. |
| Numerical Recipes, the complementary error function | published algorithm | `htm/util/erfc.pony` is the standard approximation, written out rather than called from a maths library. |

This library itself is MPL-2.0. Copyright of a translated file stays with the
upstream's authors where the translation is theirs.

## From the Go reference

Everything in this section comes from the Go reference, in one of two degrees.
A **translation** keeps the upstream's structure as well as its answers: the
same functions, the same arithmetic, the same names where Pony allows them. A
file that **follows** an upstream file keeps its answers but is arranged in this
repository's terms - a column here is an object with synapses rather than a row
of a permanence matrix - usually because the actor layer needs the data to cross
an actor boundary as a value.

| this file | from | degree | notes |
| --- | --- | --- | --- |
| `htm/dense_binary_matrix.pony` | `denseBinaryMatrix.go` | translated | |
| `htm/sparse_binary_matrix.pony` | `sparseBinaryMatrix.go` | translated | |
| `htm/util/bool_array.pony` | `utils/utils.go` | translated | the fill, count and equality helpers |
| `htm/encoders/scalar_encoder.pony` | `encoders/scalerEncoder.go` | translated | including `decode`, which is still one long function here |
| `htm/encoders/scalar_encoder_params.pony`, `scalar_range.pony`, `encoder_interfaces.pony`, `noop_encoders.pony` | `encoders/scalerEncoder.go` | translated | split out of one Go file into the pieces Pony wants |
| `htm/encoders/date_encoder.pony`, `date_encoder_params.pony` | `encoders/dateEncoder.go` | translated | |
| `htm/inhibition.pony` | `spatialPooler.go` | translated | `InhibitColumns`, global and local |
| `htm/topology.pony` | `spatialPooler.go` and `utils/utils.go` | translated | `getNeighborsND`, `RevCumProdInt`, `Mod`, `CartProductInt` |
| `htm/spatial_pooler_config.pony` | `spatialPooler.go` | translated | `SpParams`, renamed and documented |
| `htm/temporal_memory_params.pony` | `temporalMemory.go` | translated | the settings, split out of the driver |
| `htm/temporal_segment.pony` | `segment.go` | translated | the segment's arithmetic, which the memory hands it |
| `htm/temporal_synapse.pony` | `temporalMemoryConnections.go` | translated | a distal synapse |
| `htm/column.pony`, `htm/synapse.pony` | `spatialPooler.go` | follows | a column's synapses and its overlap, held as objects |
| `htm/column_learning.pony`, `htm/tie_breaker.pony` | `spatialPooler.go` | follows | the learning state and the tie-break rules, apart from the columns they judge |
| `htm/spatial_pooler.pony` | `spatialPooler.go` | follows | one process and one actor must agree, so the steps are separated rather than interleaved |
| `htm/temporal_memory.pony` | `temporalMemory.go` | follows | per-column work is an object, so the memory can be sharded across actors |
| `htm/temporal_column.pony` | `temporalMemory.go` | follows | one column of the memory, which the Go file holds as arrays |
| `htm/temporal_segment.pony`, `htm/synapses.pony` | `segment.go`, `temporalMemoryConnections.go` | follows | `Segment`, `Synapse`, `TmSynapse` |
| `htm/temporal_pooler.pony`, `temporal_pooler_config.pony` | `temporalPooler.go` | follows | `TemporalPoolerParams`, without the statistics and printing settings |
| `htm/cla_cell.pony`, `cla_segment.pony`, `cla_segment_update.pony`, `cla_state.pony` | `temporalPooler.go`, `segmentUpdate.go` | follows | `SegmentUpdate`, `UpdateState`, and the cells and segments the pooler keeps |

Deliberately **not** ported from the reference: `temporalPoolerStats.go` and
`temporalPoolerPrint.go` (statistics and printing belong to the pages that
print, not to the computation) and `trivialPredictor.go` as a library type - the
idea of it is what `examples/prediction-baselines` measures instead.

## Written from another library's account

These follow an algorithm that exists in an AGPL library, and were written from
what that library says the algorithm is. They are not translations, they produce
different bits by design, and where the upstream ships a golden-bits test, that
test is deliberately absent here.

| this file | follows | what differs |
| --- | --- | --- |
| `htm/encoders/grid_cell_encoder.pony` | `htm.core`'s `GridCellEncoder` | this repository's cells and phases, so the golden bits are not theirs. What is held to the same standard is the relation: a one-unit move keeps about three quarters of the cells. |
| `htm/encoders/simhash_document_encoder.pony` | `htm.core`'s `SimHashDocumentEncoder` | own token digest instead of SHAKE256, so the bits differ. The properties are what the tests state. |
| `htm/sdr_merger.pony` | `htm.core`'s SDR merger | two operations, not three: the third has no caller here and no clear account. |

## Read for comparison, written here

`htm/encoders/sdr_category_encoder.pony` follows the shape `htm.java` and
`nupic` use for a fixed-width category encoder - `w` random bits of a fixed
width `n` per label, labels added as they are met - because that shape is what a
stream of unknown length wants. The closed-set `category_encoder.pony` beside it
is this repository's own, and the two are deliberately not comparable.

`htm/encoders/random_distributed_scalar.pony`, `htm/sdr_classifier.pony` and
`htm/anomaly_likelihood.pony` are the NuPIC line's ideas (a bucket-to-bits map,
one weight layer with a softmax, and a rolling normal estimate) written against
this library's vocabulary. No line-by-line provenance is claimed for them.

## Original to this repository

Everything below exists because this library is actor-native, or because it is a
measurement rather than a port, and has no upstream file to compare against.

- **The actor layer**: `ballot_box.pony`, `pooler.pony`, `column_shard.pony`,
  `temporal_shard.pony`, `temporal_region.pony`, `temporal_pooler_actor.pony`,
  `anomaly_stream.pony`, `streaming_anomaly_detector.pony`, `retry.pony`,
  `dimensions.pony`, `htm_types.pony`. The algorithms are the reference's; the
  messages, the deadline-and-retry, and the "one process and actors must agree
  exactly" rule are this repository's. [Actors](actors.md) is the design.
- **The value types**: `temporal_output.pony`, `cla_output.pony`,
  `cla_forecast.pony`, `prediction_classifier.pony`. An answer that crosses an
  actor boundary has to be a value, which the reference never needed.
- **The picture side**: `htm/encoders/image_fingerprint.pony`,
  `difference_hash.pony`, `image_encoder.pony`, `picture_encoder.pony`,
  `grayscale_image.pony`, `image_decoder.pony`, `image_encoder_params.pony`,
  `graph_encoder.pony`. Difference hashing is a known technique and this is a
  plain implementation of it; the graph encoder has no upstream at all - that
  was checked across all five implementations in this workspace.
- **The examples and the studies**: see below.

## Tests

A test that translates an upstream test says so in its first line. A test that
states behaviour this repository chose is not a translation, and does not claim
to be: the actor tests compare two paths rather than a stored expectation, which
is a question the reference never asks.

| this test | from |
| --- | --- |
| `dense_binary_matrix_test.pony` | `denseBinaryMatrix_test.go` |
| `sparse_binary_matrix_test.pony` | `sparseBinaryMatrix_test.go` |
| `scalar_encoder_test.pony` | `encoders/scalerEncoder_test.go` |
| `date_encoder_test.pony` | `encoders/dateEncoder_test.go` |
| `wiring_test.pony` | `spatialPooler_test.go` (`TestPermanenceInit`, `TestRaisePermanenceThreshold`) |
| `spatial_pooler_test.pony` | `spatialPooler_test.go`, `spatialPoolerCompute_test.go` |
| `spatial_pooler_learning_test.pony`, `pooler_learning_test.pony` | `spatialPoolerBoost_test.go` |
| `temporal_memory_test.pony` | `temporalMemory_test.go` (`TestPickCellsToLearnOn`, `TestAdaptSegment`, `TestLeastUsedCell`) |
| `temporal_pooler_test.pony` | `temporalPooler_test.go` (`TestLearnPredict`) |

Everything else in `test/` states this library's own behaviour - the actor
paths, the pooler's forecast, the anomaly stream, the encoders that were written
rather than translated - and says what it is asserting in the test's name.

## Examples, and what each one is for

Each example opens `main.pony` with a docstring that says what it does and ends
with a paragraph beginning *Expect*, saying what the run should show; the run's
first line repeats the summary sentence, so the output explains itself. This
table is the index to those paragraphs.

| example | the question it answers | what to look for |
| --- | --- | --- |
| `first-representation` | what does one number become? | neighbouring values share most of their columns; 0.6 and 0.9 share few |
| `in-process-pooler` | what is the pooler without actors doing? | each column reaches a different part of the input, and the same seed gives the same answer |
| `pooler-learning` | what changes when a pooler learns? | the winning column's permanences rise towards the input, losing columns get boosted, and an inference-only round changes nothing |
| `actor-pooler` | does sharding the columns change the answer? | the two paths agree on every round |
| `scalar-encoder` | how does one number become bits? | the block of set bits slides, so neighbours overlap |
| `grid-cells` | how does a place become cells? | about three quarters of the cells survive a one-unit move, fewer beyond the shortest period |
| `document-similarity` | how does a document become bits? | sentences that share words share positions; an unrelated one shares almost none |
| `image-similarity` | does a representation survive scale and brightness? | the first three pictures are identical, the fourth is not |
| `image-retrieval` | does the representation find pictures of the same class? | well above chance and well short of retrieval: 17.3% against 9.7%, on imagenette, a corpus the fetch script downloads |
| `temporal-memory` | does the memory predict what follows? | a predicted column activates one cell instead of bursting |
| `temporal-memory-on-actors` | does the sharded memory answer the same? | every step agrees with the in-process one |
| `temporal-pooler` | what does pooling add? | the forecast three steps out names the patterns that follow, and asking changes nothing |
| `temporal-pooler-recovery` | what happens when a sequence breaks? | ten active cells rather than the eighty a burst turns on |
| `anomaly-stream` | what does an anomaly score look like? | it falls as the pattern is learned and jumps when it breaks |
| `anomaly-likelihood` | when is a score surprising? | only the odd step comes near certainty |
| `anomaly-on-actors` | is the same reading available on actors? | the score and the likelihood arrive together, and match the in-process stream |
| `boosting-value` | what does boosting buy? | columns never heard fall to nought with boosting and never move without it |
| `pooler-training-value` | what does pooler learning buy a memory? | the learned pooler keeps more of the answer, on every seed printed |
| `pooler-settings-value` | what do the pooler's settings cost? | pooling names more of the cycle and grows more segments; the re-play buys a precise state |
| `sequence-training-value` | does a learned representation help a damaged sequence? | a small but consistent edge to the learned pooler, on three seeds of five |
| `prediction-baselines` | is a memory better than not learning? | it is, on symbols; on a smooth value the last input wins |

The measurement studies - the last five - are pinned: their printed numbers are
stored in `test/fixtures/studies/` and a run that disagrees fails. That is what
makes "what to look for" checkable rather than aspirational.
