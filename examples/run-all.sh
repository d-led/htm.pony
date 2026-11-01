#!/bin/sh
# Builds and runs every example under examples/. Each example is its own
# package, so each one is built from its own directory.
set -e

root=$(cd "$(dirname "$0")" && pwd)

for example in first-representation in-process-pooler actor-pooler scalar-encoder image-similarity; do
    echo "=== $example ==="
    cd "$root/$example"
    corral run -- ponyc --debug -o . .
    "./$example"
    echo
done
