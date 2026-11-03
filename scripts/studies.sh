#!/bin/sh
# Runs the studies whose numbers are quoted in the documentation, keeps what each
# one printed in build/studies/, and checks it against the numbers published last.
#
# Their output is deterministic - every study is seeded and none of them reads a
# clock - so the files are worth keeping: CI publishes them as an artifact on
# every push to master, and the tables in docs/examples.md are read from that
# published run rather than from whichever machine happened to run them.
#
# The comparison is the point of the fixture. A change to the pooler moves these
# numbers and the documentation quotes them, so a run that no longer matches what
# is written down has to fail somewhere rather than quietly disagree.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/studies"
expected="$root/test/fixtures/studies"
mkdir -p "$out"

status=0

for study in pooler-training-value sequence-training-value boosting-value pooler-settings-value prediction-baselines; do
    echo "=== $study ==="
    cd "$root/examples/$study"
    corral run -- ponyc -o . .
    "./$study" > "$out/$study.txt"
    cat "$out/$study.txt"

    if [ -f "$expected/$study.txt" ]; then
        if ! diff -u "$expected/$study.txt" "$out/$study.txt"; then
            echo
            echo "The $study numbers no longer match test/fixtures/studies/."
            echo "If the change was intended, copy it over and bring the tables"
            echo "in docs/examples.md with it:"
            echo "    cp build/studies/$study.txt test/fixtures/studies/"
            status=1
        fi
    fi

    echo
done

exit $status
