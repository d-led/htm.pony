use "files"
use "time"

use "../../htm/encoders"
use "../../htm/measure"

actor Main
  """
  Does the picture representation find pictures of the same kind?

  A corpus of real photographs, one directory per class, is read off the disk:
  every picture is decoded, fingerprinted, and turned into a representation.
  Then every picture is used as a query against every other, and the report
  says how often the nearest picture is of the same class, how many pictures of
  other classes come before it, and how far apart the two classes of distance
  sit.

  No corpus is stored in this repository. `scripts/fetch-images.sh` puts one in
  the ignored `data/` directory; point this program at a directory of your own
  instead by passing it as the first argument, or with `HTM_PONY_IMAGES`.

  Run from this directory: `./image-retrieval`, or `./image-retrieval
  ../../data/imagenette2-160/val`.

  Expect the nearest picture to be a classmate most of the time, own-class
  distances to sit well below other-class distances, and the two to get closer
  together as the classes get alike: a difference hash keeps the outline of a
  thing and forgets everything else, which is why a ten-class corpus separates
  cleanly and a corpus of one thing does not.
  """
  let _per_class: USize = 30
  let _positions: USize = 256

  new create(env: Env) =>
    try
      let path: String val = _path(env)
      let root: FilePath val = FilePath(FileAuth(env.root), path)

      let started: U64 = Time.nanos()
      let loaded = ImageCorpus.load(root, _per_class)
      let seconds: F64 = _seconds_since(started)

      match loaded
      | let corpus: Corpus val => _report(env, path, corpus, seconds)?
      | NotAFolder =>
        env.out.print(path + " is not a directory")
        env.out.print("fetch a corpus with: ./scripts/fetch-images.sh")
      | NoPictures =>
        env.out.print(path + " holds no class directory with a picture in it")
      end
    else
      env.out.print("could not read the corpus")
      env.exitcode(1)
    end

  fun _path(env: Env): String val =>
    """
    The corpus to read: the first argument, then `HTM_PONY_IMAGES`, then where
    the fetch script puts the one it downloads.
    """
    try
      return recover val env.args(1)? end
    end
    match _from_environment(env, "HTM_PONY_IMAGES")
    | let found: String val => return found
    end
    "../../data/imagenette2-160/train"

  fun _from_environment(env: Env, name: String val): (String val | None) =>
    """
    The value of an environment variable, or None when it is not set.

    `Env.vars` is the environment as it arrived, one `NAME=value` string per
    entry, so looking one up is a prefix match rather than a dictionary.
    """
    let prefix: String val = name + "="
    for entry in env.vars.values() do
      if entry.at(prefix, 0) then
        return recover val entry.trim(prefix.size()) end
      end
    end

  fun _report(
    env: Env,
    path: String,
    corpus: Corpus val,
    seconds: F64)
    : None ?
  =>
    let encoder = ImageEncoder(ImageEncoderParams(_positions, 64 where seed' = 7))?
    let started: U64 = Time.nanos()
    let representations: USize = _encode_all(encoder, corpus)
    let encoding_seconds: F64 = _seconds_since(started)
    let scores: Scores val = _score(corpus)?

    env.out.print(path)
    env.out.print(
      _pad("classes", 12) + corpus.class_count().string()
        + ", up to " + _per_class.string() + " pictures each")
    env.out.print(
      _pad("pictures", 12) + corpus.size().string()
        + ", " + corpus.refused.string() + " refused")
    env.out.print(
      _pad("read", 12) + _rate(corpus.size().f64(), seconds)
        + " pictures/s (decode + fingerprint)")
    env.out.print(
      _pad("encoded", 12) + _rate(representations.f64(), encoding_seconds)
        + " pictures/s (" + _positions.string() + " positions each)")
    env.out.print("")
    env.out.print(
      _pad("", 20) + _pad("own class", 12) + "other classes")
    env.out.print(
      _pad("mean distance", 20) + _pad(_one(scores.own), 12)
        + _one(scores.other))
    env.out.print("")
    env.out.print(
      _pad("", 32) + _pad("this corpus", 12) + "by chance")
    env.out.print(
      _pad("nearest is a classmate", 32) + _pad(_percent(scores.top1), 12)
        + _percent(_chance_top(1, corpus)))
    env.out.print(
      _pad("a classmate in the first five", 32) + _pad(_percent(scores.top5), 12)
        + _percent(_chance_top(5, corpus)))
    env.out.print(
      _pad("pictures before a classmate", 32) + _one(scores.before))
    env.out.print(
      _pad("queries", 32) + corpus.size().string())
    env.out.print("")

  fun _chance_top(k: USize, corpus: Corpus val): F64 =>
    """
    What a ranking that knew nothing would give: the chance that the first `k`
    of a random order include a picture of the query's own class.

    Drawn without replacement, because a picture cannot be its own neighbour,
    which is what makes the first five worth less than five times the first
    one.
    """
    let others: F64 = (corpus.size() - 1).f64()
    let classmates: F64 =
      (corpus.size() - corpus.class_count()).f64() / corpus.class_count().f64()
    var none: F64 = 1.0
    var drawn: USize = 0
    while drawn < k do
      none = none * ((others - classmates - drawn.f64()) / (others - drawn.f64()))
      drawn = drawn + 1
    end
    1.0 - none

  fun _encode_all(encoder: ImageEncoder val, corpus: Corpus val): USize =>
    var encoded: USize = 0
    for picture in corpus.pictures.values() do
      try
        encoder.encode_fingerprint(picture.fingerprint)?
        encoded = encoded + 1
      end
    end
    encoded

  fun _score(corpus: Corpus val): Scores val ? =>
    let queries: USize = corpus.size()
    var top1: USize = 0
    var top5: USize = 0
    var before: F64 = 0.0
    var own: F64 = 0.0
    var other: F64 = 0.0
    var query: USize = 0
    while query < queries do
      let candidates: Array[(USize, String val)] = _candidates(corpus, query)?
      let own_label: String val = corpus.pictures(query)?.label
      let obstacles: USize = Retrieval.obstacles(candidates, own_label)
      if obstacles == 0 then top1 = top1 + 1 end
      if obstacles < 5 then top5 = top5 + 1 end
      before = before + obstacles.f64()
      own = own + Retrieval.mean_distance(candidates, own_label, true)
      other = other + Retrieval.mean_distance(candidates, own_label, false)
      query = query + 1
    end
    Scores(
      top1.f64() / queries.f64(),
      top5.f64() / queries.f64(),
      before / queries.f64(),
      own / queries.f64(),
      other / queries.f64())

  fun _candidates(
    corpus: Corpus val,
    query: USize)
    : Array[(USize, String val)] ?
  =>
    let asked: CorpusImage val = corpus.pictures(query)?
    let candidates: Array[(USize, String val)] =
      Array[(USize, String val)](corpus.size() - 1)
    for (index, picture) in corpus.pictures.pairs() do
      if index != query then
        candidates.push((asked.hamming(picture)?, picture.label))
      end
    end
    candidates

  fun _seconds_since(started: U64): F64 =>
    (Time.nanos() - started).f64() / 1000000000.0

  fun _rate(count: F64, seconds: F64): String =>
    if seconds <= 0.0 then return "-" end
    _whole(count / seconds)

  fun _whole(value: F64): String =>
    (value.round().i64()).string()

  fun _one(value: F64): String =>
    let tenths: I64 = (value * 10.0).round().i64()
    (tenths / 10).string() + "." + (tenths % 10).string()

  fun _percent(share: F64): String =>
    _one(share * 100.0) + "%"

  fun _pad(text: String, width: USize): String val =>
    let padded: String iso = recover iso String(width) end
    padded.append(text)
    var added: USize = text.size()
    while added < width do
      padded.append(" ")
      added = added + 1
    end
    consume padded

class val Scores
  """
  What one pass over a corpus said, as shares and means rather than counts, so
  the figures do not have to be re-divided to be compared with another corpus.
  """
  let top1: F64
  let top5: F64
  let before: F64
  let own: F64
  let other: F64

  new val create(top1': F64, top5': F64, before': F64, own': F64, other': F64) =>
    top1 = top1'
    top5 = top5'
    before = before'
    own = own'
    other = other'
