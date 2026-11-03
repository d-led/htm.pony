#!/usr/bin/env bash
# Fetch a picture corpus for the image-retrieval benchmark.
#
# Nothing in this repository is a dataset: `data/` is ignored, and this script
# is what puts something in it. The default is imagenette, ten classes of real
# photographs, one directory per class, Apache-2.0, about 100 MB.
#
#   scripts/fetch-images.sh                    # imagenette2-160 into data/
#   scripts/fetch-images.sh imagenette2-320    # the larger pictures
#   HTM_PONY_DATA=/somewhere scripts/fetch-images.sh
#
# Point the benchmark at any corpus of your own instead by giving it a root
# directory of one directory per class; nothing here is required for that.

set -euo pipefail

dataset="${1:-imagenette2-160}"
data_root="${HTM_PONY_DATA:-$(cd "$(dirname "$0")/.." && pwd)/data}"
archive="https://s3.amazonaws.com/fast-ai-imageclas/${dataset}.tgz"
target="${data_root}/${dataset}"

if [ -d "${target}/train" ]; then
  echo "already fetched: ${target}"
  exit 0
fi

mkdir -p "${data_root}"
echo "fetching ${archive}"
curl -fL --progress-bar "${archive}" -o "${data_root}/${dataset}.tgz"
echo "unpacking into ${data_root}"
tar xzf "${data_root}/${dataset}.tgz" -C "${data_root}"
rm -f "${data_root}/${dataset}.tgz"

echo "pictures: $(find "${target}/train" -type f | wc -l | tr -d ' ') in train, \
$(find "${target}/val" -type f | wc -l | tr -d ' ') in val"
echo "now: ./examples/image-retrieval/run.sh"
