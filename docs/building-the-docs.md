# Building the documentation

The pages under `docs/` are written by hand. The API reference under
`docs/reference/api/` is generated from the source and is not committed.

## One-time setup

```
python3 -m venv .venv-docs
./.venv-docs/bin/pip install mkdocs-material
```

Pony 0.77 or later provides `pony-doc`. It ships inside the compiler release, so
installing the compiler with ponyup is enough.

## Generate and serve

```
python3 scripts/api-reference.py
./.venv-docs/bin/mkdocs serve
```

`mkdocs serve` needs the API reference to exist, because the navigation links to
it. Run the generator first, and again after changing the source.

## Check it builds

```
python3 scripts/api-reference.py
./.venv-docs/bin/mkdocs build --strict
```

`--strict` turns warnings into errors, so a broken internal link fails the build
instead of shipping.

## What the generator does

`pony-doc` writes a page for every type it compiles, which includes the whole
Pony standard library. `scripts/api-reference.py` keeps the three packages of
this repository, rewrites every standard library link to
[stdlib.ponylang.io](https://stdlib.ponylang.io/), and drops the pages it did not
keep. That turns about 460 pages into about 100, and the site does not carry a
copy of documentation that already exists elsewhere.
