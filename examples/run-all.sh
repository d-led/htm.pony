#!/bin/sh
# Builds and runs every example under examples/. Each example is its own
# package, so each one is built from its own directory.
set -e

root=$(cd "$(dirname "$0")" && pwd)

for example in first-representation in-process-pooler pooler-learning pooler-training-value pooler-settings-value boosting-value sequence-training-value actor-pooler scalar-encoder image-similarity temporal-memory temporal-memory-on-actors temporal-pooler temporal-pooler-recovery anomaly-stream anomaly-likelihood grid-cells document-similarity anomaly-on-actors prediction-baselines image-retrieval; do
    echo "=== $example ==="
    cd "$root/$example"
    corral run -- ponyc --debug -o . .
    "./$example"
    echo
done
