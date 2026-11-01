# Getting started

## Install the toolchain

[ponyup](https://github.com/ponylang/ponyup) installs the compiler and the
package manager:

```
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ponylang/ponyup/latest-release/ponyup-init.sh | sh
```

Then install the compiler and corral:

```
ponyup update ponyc release
ponyup update corral release
```

`ponyup` writes its binaries to `~/.local/share/ponyup/bin`. Put that directory
on `PATH`.

## Get the code

```
git clone https://github.com/d-led/htm.pony
cd htm.pony
```

## Run the tests

```
cd test
corral run -- ponyc --debug
./test
```

The suite prints one line per test and a summary:

```
---- Passed: 69
----
---- 69 tests ran.
---- Passed: 69
```

A non-zero exit status means something failed. The runner takes a few options:

```
./test --list                      # names the tests without running them
./test --only="spatial"            # runs tests whose names start with "spatial"
./test --verbose                   # shows the output of passing tests too
```

`--exclude=prefix`, `--sequential`, `--noprog`, `--shuffle` and `--label` are
also accepted.

## Run an example

Each example is its own package under `examples/`. Build and run it from its own
directory:

```
cd examples/in-process-pooler
corral run -- ponyc --debug
./in-process-pooler
```

That prints:

```
columns 64, inputs 64
density at radius 1: 0.222222

column   field      synapses
0       0..16      9
9       0..25      13
31      15..47     17
63      47..63     9

active input bits: 3, 5, 8, 13, 21, 44
representation:    3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56

a second pooler with the same seed gives the same representation
```

The other three examples are described in [Examples](examples.md). To build and
run all four at once, from the repository root:

```
./examples/run-all.sh
```

## Reading the code

The package is `htm/`, one file per concept, with docstrings on the types that
need them. The tests are `test/`, one file per module. `test/main.pony` holds
the list of test lists, so a new test file has to be registered there before it
runs.

## Where to go next

- [Representations](concepts/representations.md) — what a bit vector means here
- [Spatial pooler](spatial-pooler.md) — the representation algorithm
- [Actors](actors.md) — the same computation as messages
- [Tutorial](tutorial.md) — build a representation step by step
