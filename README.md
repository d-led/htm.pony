# HTM.Pony

[![CI](https://github.com/d-led/htm.pony/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/d-led/htm.pony/actions/workflows/ci.yml)

Documentation: **https://d-led.github.io/htm.pony/**

- Status: the spatial pooler and the temporal memory both work, in process and on actors; the graph encoder is not written
- based off the [Go implementation: https://github.com/htm-community/htm](https://github.com/htm-community/htm) (MIT License)
- no direct dependency on other implementations

## What works

A scalar, category, random-distributed, date or picture file goes in as bits; the
spatial pooler turns those bits into columns that recognise them; the temporal
memory learns what tends to follow what in those columns; and a classifier turns
the prediction into probabilities over categories. Every stage is tested, and
each one runs twice: once in process, and once as actors passing messages.

`examples/` walks the whole pipeline in thirteen runnable programs, and three of
them measure rather than demonstrate - what learning is worth, what a learned
pooler gives a memory, and what boosting is worth - with the numbers published by
CI so they can be checked.

Three things are deliberately absent, and the [documentation](https://d-led.github.io/htm.pony/)
says why for each: the **graph encoder** is not written, the **date encoder** has
its season field but not the other four, and the **CLA temporal pooler** is not
ported.

The [roadmap](https://d-led.github.io/htm.pony/roadmap/) says what this is for, in
the order it was asked for - predictions, classification, online anomaly detection
- and what comes next. The picture side is an experiment that lives in the
examples, not a feature of the pipeline.

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
- Category encoder: one block of bits per label, no overlap between labels
- Random distributed encoder: a value becomes a bucket whose neighbours differ by
  one bit, so near values overlap without a range being known in advance
- Date encoder: season, day of week, weekend, time of day and holidays, each a
  scalar field written side by side into one vector
- Grid cell encoder: a place in the plane becomes the cells a grid cell layer
  would fire, from lattices at several spacings
- Grid topology, column wiring, overlap, global and local inhibition
- Spatial pooler, in process and on actors
- Permanence learning in process and on actors: winners move towards what they
  won with, starving columns are raised and boosted, activity is remembered
- Picture encoder: difference hash over a grayscale image, turned into
  overlapping representations, and reading PNG, JPEG, BMP and GIF through
  stb_image, so nothing has to be decoded by hand
- Temporal memory: cells, segments, prediction and bursts, with segment
  punishment for predictions that do not come true, in process and on actors
- SDR classifier and prediction classifier: probabilities over categories, and
  the label of the next step
- Streaming anomaly detection: the share of active columns that had to burst,
  and how unusual that share is given the scores that came before it
- Runnable examples under `examples/`, described in the
  [documentation](https://d-led.github.io/htm.pony/examples/)
- Two microbenchmarks over one matrix, comparing `row_and_sum` on the dense and
  the sparse matrix at the same density
- Not started: the graph encoder

The [documentation](https://d-led.github.io/htm.pony/) says what each of these
actually does, including the parts that are present but empty.

## Developing

- [Install Ponyc](https://github.com/ponylang/ponyc/blob/master/README.md#installation)
- Compilation: `ponyc` from the test folder produces the test executable

## Dependencies

- the standard library, and nothing else: date and time come from `time`, which
  derives the calendar fields from a POSIX timestamp
- the picture decoder vendors [stb_image](https://github.com/nothings/stb) (public
  domain, or MIT where a jurisdiction does not allow that), which is compiled
  beside the package it belongs to

## License

- [Mozilla Public License 2.0](LICENSE): file-level copyleft, so changes to these
  files stay open while the library can be used in software that is not
- the port follows the [Go implementation](https://github.com/htm-community/htm),
  which is MIT (Copyright (c) 2014 Zac Gross); the MIT notice covers the parts
  that came from it
- See also, [Numenta Licenses](https://numenta.org/licenses/)
