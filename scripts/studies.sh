#!/bin/sh
# Runs every measurement example, keeps what each printed as markdown, and
# checks the numbers against the ones published last.
#
# The studies are seeded and read no clock, so their output is worth keeping:
# `docs/results/` is what the documentation renders, and CI republishes it on
# every push, so nobody copies numbers by hand. `test/fixtures/studies/` is the
# deliberate copy: a change to the pooler moves those numbers, and a run that no
# longer matches them has to fail somewhere rather than quietly disagree with
# what is written down.
#
# A study prints markdown. One that still prints an aligned text table is kept
# in a fenced block, so the file is markdown either way.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/studies"
expected="$root/test/fixtures/studies"
results="$root/docs/results"
mkdir -p "$out" "$expected" "$results"

status=0

# The one list of the measurement examples. examples/run-all.sh reads it to know
# which ones to leave out when CI runs the demonstrations, so a study added here
# is picked up by both.
studies="pooler-training-value sequence-training-value boosting-value pooler-settings-value prediction-baselines image-robustness"

markdown_of() {
    # $1 is what the study printed, $2 where the markdown goes, $3 its name.
    if grep -q '^==== markdown ====$' "$1"; then
        awk '/^==== markdown ====$/{found=1; next} found' "$1" > "$2"
    else
        {
            echo "#### $3"
            echo
            echo '```text'
            cat "$1"
            echo '```'
        } > "$2"
    fi
}

for study in $studies; do
    echo "=== $study ==="
    cd "$root/examples/$study"
    corral run -- ponyc -o . .
    "./$study" > "$out/$study.txt"
    markdown_of "$out/$study.txt" "$out/$study.md" "$study"
    cat "$out/$study.md"

    if [ -f "$expected/$study.md" ]; then
        if ! diff -u "$expected/$study.md" "$out/$study.md"; then
            echo
            echo "The $study numbers no longer match test/fixtures/studies/."
            echo "If the change was intended, take it as the new record:"
            echo "    cp build/studies/$study.md test/fixtures/studies/"
            echo "docs/results/ has already been updated by this run."
            status=1
        fi
    fi

    cp "$out/$study.md" "$results/$study.md"
    echo
done

exit $status
