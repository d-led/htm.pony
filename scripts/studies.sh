#!/bin/sh
# Runs the studies whose numbers are quoted in the documentation, and keeps what
# each one printed in build/studies/.
#
# Their output is deterministic - every study is seeded and none of them reads a
# clock - so the files are worth keeping: CI publishes them as an artifact on
# every push to master, and the tables in docs/examples.md are read from that
# published run rather than from whichever machine happened to run them. A
# machine under load leaks into wall-clock measurements; these are not ones.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/studies"
mkdir -p "$out"

for study in pooler-training-value sequence-training-value boosting-value; do
    echo "=== $study ==="
    cd "$root/examples/$study"
    corral run -- ponyc -o . .
    "./$study" > "$out/$study.txt"
    cat "$out/$study.txt"
    echo
done
