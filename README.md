# HTM.Pony

[![CI](https://github.com/d-led/htm.pony/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/d-led/htm.pony/actions/workflows/ci.yml)

Documentation: **https://d-led.github.io/htm.pony/**

- Status: the spatial pooler works; the temporal memory is not written yet
- based off the [Go implementation: https://github.com/htm-community/htm](https://github.com/htm-community/htm) (MIT License)
- no direct dependency on other implementations

## What works

The spatial pooler runs end to end: columns are wired to receptive fields, overlap
counts the active inputs a column is connected to, and inhibition chooses which
columns represent the input. Global and local inhibition are both implemented, and
wiring takes a seed, so a seed and an input always give the same representation.

The same computation also runs on messages. Column shards push their votes into a
ballot box, which closes a round when every vote has arrived, when a quorum has
arrived, or when a deadline expires. A pooler coordinator inhibits the tally and
pushes the representation back to whoever asked.

Not implemented yet: permanence learning, duty cycles and boosting; the temporal
memory; the CLA temporal pooler.

## Rough Plan

- Port the [Go version](https://github.com/htm-community/htm) to Pony
- Parallelize where the computation allows it, with actors carrying the work
- When the Temporal Pooler is ported, align the implementation with the latest NuPIC/htm.java details
- Error handling is ad hoc currently, and will need to be designed once there is a high level executable that uses the library. Trade-offs: [errors, logging & partial functions](https://tutorial.ponylang.io/expressions/exceptions.html) vs explicit [union return types](https://tutorial.ponylang.io/types/type-expressions.html)

## Contributing

- Open or take an issue for the next small problem to solve, and open a PR if there's some code to be merged
- If there are tests and these pass in CI, the maintainers should merge the PR into master
- After a successful PR, the contributor may become a maintainer if so desired
- Should merge conflicts arise, the master will be protected, all work will be done via PRs
- Long-lived branches are to be avoided. All progress should go into the master branch as soon as the tests are green
- If there's significant traction, we'll switch to the [ZeroMQ](https://github.com/zeromq/czmq/blob/master/CONTRIBUTING.md) process [C4](https://rfc.zeromq.org/spec:22/C4/) and a protected master

### Getting Started with Pony

- see [ponyc Readme](https://github.com/ponylang/ponyc#windows-using-zip-via-bintray)

### Current Maintainers

- [Dmitry Ledentsov/d-led](https://github.com/d-led)

## Progress

- Dense and sparse binary matrices, with the Go tests translated
- Scalar encoder, including decoding
- Date encoder: the season field is encoded; the other four reserve width but are
  not written
- Grid topology, column wiring, overlap, global and local inhibition
- Spatial pooler, in process and on actors
- Picture encoder: difference hash over a grayscale image, turned into
  overlapping representations, and reading PNG, JPEG, BMP and GIF through
  stb_image, so nothing has to be decoded by hand
- Temporal memory: cells, segments, prediction and bursts, with segment
  punishment for predictions that do not come true
- SDR classifier and prediction classifier: probabilities over categories, and
  the label of the next step
- Streaming anomaly detection: the share of active columns that had to burst
- Runnable examples under `examples/`, described in the
  [documentation](https://d-led.github.io/htm.pony/examples/)
- Not started: permanence learning, duty cycles, boosting, the temporal memory on
  actors, the category and RDSE encoders, the benchmarks, smoothing the anomaly
  score into a likelihood

The [documentation](https://d-led.github.io/htm.pony/) says what each of these
actually does, including the parts that are present but empty.

## Developing

- [Install Ponyc](https://github.com/ponylang/ponyc/blob/master/README.md#installation)
- Compilation: `ponyc` from the test folder produces the test executable

## Dependencies

- date/time construction: [slayful/sagittarius](https://github.com/slayful/sagittarius) (license yet unspecified)

## License

- See [LICENSE](LICENSE)
- See also, [Numenta Licenses](https://numenta.org/licenses/)
