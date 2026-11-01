#!/usr/bin/env python3
"""Generate the API reference for this project's packages.

pony-doc emits a page for every type it compiles, which includes the whole Pony
standard library and every dependency. Those pages are not ours to host: they
are published at https://stdlib.ponylang.io with exactly the same file naming,
so a link to a standard library type becomes a link to that site.

Only the three packages of this repository are kept, plus sagittarius, which is
a dependency with no published documentation site of its own.
"""

import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "pony-doc"
OUT = ROOT / "docs" / "reference" / "api"
STDLIB = "https://stdlib.ponylang.io"

# package directory, and the prefix pony-doc gives its pages
PACKAGES = [
    ("htm", "htm"),
    ("htm/encoders", "encoders"),
    ("htm/encoders/stb", "stb"),
    ("htm/util", "util"),
]

# pony-doc prefixes a package it reached as a dependency with a dash, and joins
# the path with dashes: deps/sagittarius/sagittarius becomes -deps-sagittarius-sagittarius
OWNERS = [
    (re.compile(r"^-htm-util-(.+)$"), "util"),
    (re.compile(r"^-htm-(.+)$"), "htm"),
    (re.compile(r"^(-?)deps-sagittarius-sagittarius-(.+)$"), "sagittarius"),
    (re.compile(r"^htm-(.+)$"), "htm"),
    (re.compile(r"^encoders-(.+)$"), "encoders"),
    (re.compile(r"^util-(.+)$"), "util"),
    # The stb package imports its parent, and pony-doc names those pages after the
    # relative import: they belong to encoders, which has already written them.
    (re.compile(r"^stb-\.\.-(.+)$"), "encoders"),
    (re.compile(r"^stb-(.+)$"), "stb"),
]

LINK = re.compile(r"\]\(([^)\s]+)\)")

# pony-doc sometimes attributes a dependency's source file to the package being
# documented, and writes a link to a page it never emitted. Those links are
# removed rather than left dangling.
SOURCE_SPAN = re.compile(
    r'<span class="source-link">\[\[Source\]\]\(([^)]*)\)</span>'
)


def owner(filename):
    """Which package a generated page belongs to, or None if it is standard library."""
    for pattern, name in OWNERS:
        match = pattern.match(filename)
        if match:
            return name, match.group(match.lastindex)
    return None, None


def page_name(filename):
    """The name a page gets in this site, or None when the page is not ours."""
    stem, _, anchor = filename.partition("#")
    if not stem.endswith(".md"):
        return None
    name, rest = owner(stem[: -len(".md")])
    if name is None:
        return None
    return f"{name}-{rest}.md"


def source_name(path):
    """The name a source page gets, mirroring the package layout."""
    parts = Path(path).parts
    if len(parts) < 3 or parts[0] != "src":
        return None
    package, rest = parts[1], parts[2:]
    renamed = {
        "-htm": "htm",
        "-htm-util": "util",
        "-deps-sagittarius-sagittarius": "sagittarius",
        "htm": "htm",
        "encoders": "encoders",
        "stb": "stb",
        "util": "util",
    }.get(package)
    if renamed is None:
        return None
    return Path("src", renamed, *rest).as_posix()


def generate(package):
    """Run pony-doc for one package and return the directory it wrote.

    PONY_DOC may name a command to run instead of a local pony-doc, which is how
    CI reaches the compiler through the ponyc image. Paths are relative to the
    repository so the same arguments work on both sides of a container mount.
    """
    target = WORK / package.replace("/", "-")
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir(parents=True)

    command = shlex.split(os.environ.get("PONY_DOC", "pony-doc"))
    command += ["-b", "mkdocs", "-o", str(target.relative_to(ROOT)), package]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"pony-doc failed for {package}:\n{result.stdout}{result.stderr}")
    written = list(target.glob("*-docs"))
    if not written:
        sys.exit(f"pony-doc wrote nothing for {package}")
    return written[0] / "docs"


def copy_pages(generated, kept):
    """Copy the pages that belong to this project into the output directory.

    The first run for a package wins: the encoders run reaches htm as a
    dependency, and its copy of those pages is the same page.
    """
    for page in sorted(generated.glob("*.md")):
        name = page_name(page.name)
        if name is None or name in kept:
            continue
        kept.add(name)
        shutil.copyfile(page, OUT / name)

    source_root = generated / "src"
    if not source_root.is_dir():
        return
    for page in sorted(source_root.rglob("*.md")):
        relative = source_name(page.relative_to(generated).as_posix())
        if relative is None:
            continue
        destination = OUT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.copyfile(page, destination)


def rewrite_links(kept):
    """Point every standard library link at stdlib.ponylang.io.

    A link to one of our own pages is renamed to match the name it was copied
    under. Anything else is a standard library type, and the file name it was
    generated with is the same name the standard library site uses.
    """
    for page in sorted(OUT.rglob("*.md")):
        text = page.read_text()

        def replace(match):
            target = match.group(1)
            path, _, anchor = target.partition("#")
            suffix = f"#{anchor}" if anchor else ""

            if path.startswith("http") or not path.endswith(".md"):
                return match.group(0)
            if path.startswith("src/"):
                renamed = source_name(path)
                return f"]({renamed}{suffix})" if renamed else match.group(0)

            name = page_name(path)
            if name in kept:
                return f"]({name}{suffix})"
            return f"]({STDLIB}/{path[:-3]}/{suffix})"

        page.write_text(LINK.sub(replace, text))


def drop_dangling_sources():
    """Remove source links whose target page does not exist."""
    for page in sorted(OUT.rglob("*.md")):
        text = page.read_text()

        def drop(match):
            target = match.group(1).split("#")[0]
            return match.group(0) if (OUT / target).exists() else ""

        page.write_text(SOURCE_SPAN.sub(drop, text))


LABELS = {
    "htm": "htm — the core package",
    "encoders": "htm/encoders",
    "stb": "htm/encoders/stb",
    "util": "htm/util",
    "sagittarius": "sagittarius — a dependency",
}


def write_index(kept):
    """pony-doc writes one index per package; collect them so the site has a way in."""
    indexes = sorted(name for name in kept if name.endswith("--index.md"))
    if not indexes:
        return
    entries = "".join(
        f"- [{LABELS.get(name[:-10], name[:-10])}]({name})\n" for name in indexes
    )
    (OUT / "index.md").write_text(
        "# API reference\n"
        "\n"
        "Generated from the source by `pony-doc`, one page per type. Standard"
        " library types link to"
        f" [stdlib.ponylang.io]({STDLIB}/).\n"
        "\n" + entries
    )


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)

    kept = set()
    for package, _ in PACKAGES:
        copy_pages(generate(package), kept)

    rewrite_links(kept)
    drop_dangling_sources()
    write_index(kept)

    pages = list(OUT.rglob("*.md"))
    size = sum(page.stat().st_size for page in pages)
    print(f"{len(pages)} pages, {size / 1024:.0f} KiB in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
