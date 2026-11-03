#!/bin/sh
# Builds and runs every example under examples/. Each example is its own
# package, so each one is built from its own directory.
#
# `--demos-only` leaves out the measurement examples, which
# `scripts/studies.sh` builds and runs in a release build anyway: running the
# same programs twice is the largest single cost of a CI run, and a debug build
# of the place-code benchmark alone takes a minute and a half. The studies list
# is read from that script rather than copied here, so the two cannot drift.
set -e

root=$(cd "$(dirname "$0")" && pwd)
studies=$(sed -n 's/^studies="\(.*\)"$/\1/p' "$root/../scripts/studies.sh")

if [ -z "$studies" ]; then
    echo "could not read the studies list from scripts/studies.sh" >&2
    exit 1
fi

skip() {
    case " $studies " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

for example in first-representation in-process-pooler pooler-learning pooler-training-value pooler-settings-value boosting-value sequence-training-value actor-pooler scalar-encoder image-similarity temporal-memory temporal-memory-on-actors temporal-pooler temporal-pooler-recovery anomaly-stream anomaly-likelihood grid-cells document-similarity anomaly-on-actors prediction-baselines image-retrieval image-robustness; do
    if [ "$1" = "--demos-only" ] && skip "$example"; then
        continue
    fi

    echo "=== $example ==="
    cd "$root/$example"
    corral run -- ponyc --debug -o . .
    "./$example"
    echo
done
