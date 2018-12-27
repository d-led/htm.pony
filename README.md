# HTM.Pony

[![Build Status](https://travis-ci.org/d-led/htm.pony.svg?branch=master)](https://travis-ci.org/d-led/htm.pony)

- Status: a small experiment, work in progress
- based off the [Go implementation: https://github.com/htm-community/htm](https://github.com/htm-community/htm) (MIT License)
- no direct dependency on other implementations

## Rough Plan

- Start with porting the [Go version](https://github.com/htm-community/htm) to Pony using classes at first
- Once an opportunity arises to parallelize, start experimenting with actors & benchmark
- When the Temporal Pooler is ported, align the implementation with the latest NuPIC/htm.java details
- No attempt at proactive refactoring is made at the moment. When a rough [working](https://twitter.com/kentbeck/status/459707016387108864) version is made, it might make sense to reimplement whole classes/actors
- continue

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

- Sparse Binary Matrix, Dense Binary Matrix: Go tests translated & running. Untested Go code left for later
- Initial implementation ready: Scalar Encoder (#1)
- Next: Date Encoder (#2), any other chunk with minimal dependencies

## Developing

- [Install Ponyc](https://github.com/ponylang/ponyc/blob/master/README.md#installation)
- Compilation: `ponyc` from the test folder produces the test executable

## Dependencies

- date/time construction: [slayful/sagittarius](https://github.com/slayful/sagittarius) (license yet unspecified)

## License

- See [LICENSE](LICENSE)
- See also, [Numenta Licenses](https://numenta.org/licenses/)
