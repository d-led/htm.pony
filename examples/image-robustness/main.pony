use "random"

use "../../htm/encoders"
use "../../htm/measure"

interface Fingerprint
  """
  A way of turning a picture into bits, so that two of them can be compared on
  the same set of distortions rather than each on its own terms.
  """
  fun name(): String
  fun bits(): USize
  fun of(image: GrayscaleImage val): ImageFingerprint val ?

class DifferenceFingerprint is Fingerprint
  fun name(): String => "difference hash"
  fun bits(): USize => DifferenceHash.bits()
  fun of(image: GrayscaleImage val): ImageFingerprint val ? =>
    DifferenceHash.compute(image)?

class AverageFingerprint is Fingerprint
  fun name(): String => "average hash"
  fun bits(): USize => AverageHash.bits()
  fun of(image: GrayscaleImage val): ImageFingerprint val ? =>
    AverageHash.compute(image)?

interface Damage
  """
  One thing that happens to a picture, and the names of it in the table and on
  a chart tick.
  """
  fun name(): String
  fun short(): String
  fun apply(image: GrayscaleImage val): GrayscaleImage val ?

class Brighter is Damage
  fun name(): String => "brighter, forty levels"
  fun short(): String => "bright"
  fun apply(image: GrayscaleImage val): GrayscaleImage val ? =>
    Distortions.brighter(image, 40)?

class Larger is Damage
  fun name(): String => "twice the size"
  fun short(): String => "double"
  fun apply(image: GrayscaleImage val): GrayscaleImage val ? =>
    Distortions.scaled(image, 2)?

class Smaller is Damage
  fun name(): String => "half the size"
  fun short(): String => "half"
  fun apply(image: GrayscaleImage val): GrayscaleImage val ? =>
    Distortions.shrunk(image, 2)?

class Cropped is Damage
  fun name(): String => "cropped, a twentieth a side"
  fun short(): String => "crop"
  fun apply(image: GrayscaleImage val): GrayscaleImage val ? =>
    let by = image.width / 20
    if by == 0 then error end
    Distortions.cropped(image, by)?

class Grainy is Damage
  let _amount: USize
  let _seed: U64

  new create(amount: USize, seed: U64) =>
    _amount = amount
    _seed = seed

  fun name(): String => "grain, " + _amount.string() + " levels"
  fun short(): String => "grain"
  fun apply(image: GrayscaleImage val): GrayscaleImage val ? =>
    Distortions.noisy(image, _amount, Rand(_seed))?

class val Measured
  """
  What one fingerprint drifted by, under each distortion, and the distance
  between two different pictures that makes those numbers readable.
  """
  let name: String val
  let bits: USize
  let damages: Array[String val] val
  let shorts: Array[String val] val
  let drift: Array[F64] val
  let apart: F64

  new val create(
    name': String val,
    bits': USize,
    damages': Array[String val] val,
    shorts': Array[String val] val,
    drift': Array[F64] val,
    apart': F64)
  =>
    name = name'
    bits = bits'
    damages = damages'
    shorts = shorts'
    drift = drift'
    apart = apart'

actor Main
  """
  How far does a fingerprint drift when the picture is distorted - and is the
  drift small next to the distance between two different pictures?

  That comparison is the whole of it. A fingerprint that survives a distortion
  is one whose distance to a distorted copy is well below its distance to an
  unrelated picture; a fingerprint that survives everything is the same for
  every picture and useless. The last row of each table is the yardstick.

  The pictures are built in code rather than read from a corpus, because the
  question is about what the hash does to pixels and not about photographs: a
  smooth gradient, a set of bars, a diagonal ramp, a ring, and a checkerboard,
  which between them cover no edges, one frequency, and detail as fine as the
  grid. `examples/image-retrieval` asks the other question, of a corpus.

  Expect brightness to cost neither hash anything, and by construction: the
  difference hash keeps only the sign of the gradient, and the average hash
  compares against a median that moves with the picture. Expect size to cost the
  average hash nothing and the difference hash a few bits, because sixteen cells
  into ninety-six pixels lands on a boundary and nine does not. Expect grain to
  cost the difference hash less, because its cells are the larger ones and the
  grain averages away before the comparison. And expect cropping to cost both
  about half of what being a different picture costs - which is the honest
  answer: a cropped copy is neither the same picture nor another one, and a hash
  that survived it would have to be built for it.
  """
  let _size: USize = 96

  new create(env: Env) =>
    try
      let pictures: Array[(String, GrayscaleImage val)] val = _pictures()?
      let damages: Array[Damage] = _damages()
      let measured: Array[Measured val] iso =
        recover iso Array[Measured val] end
      measured.push(_measure(DifferenceFingerprint, pictures, damages)?)
      measured.push(_measure(AverageFingerprint, pictures, damages)?)
      let all: Array[Measured val] val = consume measured

      _markdown(env, all)?
      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _pictures(): Array[(String, GrayscaleImage val)] val ? =>
    recover val
      let pictures: Array[(String, GrayscaleImage val)] =
        Array[(String, GrayscaleImage val)]
      pictures.push(("a diagonal ramp", Synthetic.pattern(_size, _size)?))
      pictures.push(("vertical bars", Synthetic.stripes(_size, _size)?))
      pictures.push(("a smooth gradient", Synthetic.gradient(_size, _size)?))
      pictures.push(("a ring", Synthetic.ring(_size, _size)?))
      pictures.push(("a checkerboard", Synthetic.checker(_size, _size)?))
      pictures
    end

  fun _damages(): Array[Damage] =>
    let damages: Array[Damage] = Array[Damage]
    damages.push(Brighter)
    damages.push(Larger)
    damages.push(Smaller)
    damages.push(Cropped)
    damages.push(Grainy(10, 7))
    damages

  fun _measure(
    fingerprint: Fingerprint,
    pictures: Array[(String, GrayscaleImage val)] val,
    damages: Array[Damage])
    : Measured val ?
  =>
    let originals: Array[ImageFingerprint val] =
      Array[ImageFingerprint val](pictures.size())
    for (_, picture) in pictures.values() do
      originals.push(fingerprint.of(picture)?)
    end

    let drift: Array[F64] iso = recover iso Array[F64](damages.size()) end
    for damage in damages.values() do
      drift.push(_drift(fingerprint, pictures, originals, damage)?)
    end

    Measured(
      fingerprint.name(),
      fingerprint.bits(),
      _names(damages),
      _shorts(damages),
      consume drift,
      _apart(pictures, originals)?)

  fun _names(damages: Array[Damage]): Array[String val] val =>
    let names: Array[String val] iso =
      recover iso Array[String val](damages.size()) end
    for damage in damages.values() do
      names.push(recover val damage.name() end)
    end
    consume names

  fun _shorts(damages: Array[Damage]): Array[String val] val =>
    let names: Array[String val] iso =
      recover iso Array[String val](damages.size()) end
    for damage in damages.values() do
      names.push(recover val damage.short() end)
    end
    consume names

  fun _tell(env: Env, measured: Measured val) ? =>
    """
    The table a person reads in a terminal.
    """
    env.out.print(measured.name + ", " + measured.bits.string() + " bits")
    env.out.print("")
    env.out.print(_pad("", 30) + "bits changed")

    var index: USize = 0
    while index < measured.drift.size() do
      env.out.print(
        _pad(measured.damages(index)?, 30) + _share(measured.drift(index)?))
      index = index + 1
    end
    env.out.print(_pad("a different picture", 30) + _share(measured.apart))

  fun _markdown(env: Env, measured: Array[Measured val] val) ? =>
    """
    The same numbers as markdown, and the comparison the table cannot make at a
    glance: how far a distortion moves the hash, beside how far a different
    picture is. A distortion shorter than the wide bar is one the hash survives;
    a distortion near it has cost the hash the picture.
    """
    let rows: Array[Array[String] val] iso =
      recover iso Array[Array[String] val] end
    let series: Array[(String, Array[F64] val)] iso =
      recover iso Array[(String, Array[F64] val)] end
    let shorts: Array[String val] iso = recover iso Array[String val] end

    var index: USize = 0
    while index < measured(0)?.drift.size() do
      let cells: Array[String val] iso = recover iso Array[String val] end
      cells.push(measured(0)?.damages(index)?)
      for each in measured.values() do
        cells.push(_share(each.drift(index)?))
      end
      cells.push(_share(measured(0)?.apart))
      rows.push(consume cells)
      shorts.push(measured(0)?.shorts(index)?)
      index = index + 1
    end
    // the last bar is the yardstick: what a *different* picture costs
    shorts.push(recover val "different" end)

    for each in measured.values() do
      let percents: Array[F64] iso =
        recover iso Array[F64](each.drift.size() + 1) end
      for value in each.drift.values() do
        percents.push(value * 100.0)
      end
      percents.push(each.apart * 100.0)
      series.push((each.name, consume percents))
    end

    let headers: Array[String val] iso = recover iso Array[String val] end
    headers.push("distortion")
    for each in measured.values() do
      headers.push(each.name)
    end
    headers.push("a different picture")

    env.out.print("")
    env.out.print("#### How far does a picture fingerprint drift?")
    env.out.print("")
    env.out.print(Report.table(consume headers, consume rows))
    env.out.print(Report.chart(
      "bits changed by a distortion, against being another picture",
      "% of the fingerprint's bits",
      consume shorts,
      consume series))

  fun _drift(
    fingerprint: Fingerprint,
    pictures: Array[(String, GrayscaleImage val)] val,
    originals: Array[ImageFingerprint val],
    damage: Damage)
    : F64 ?
  =>
    var changed: USize = 0
    var bits: USize = 0
    var index: USize = 0
    while index < pictures.size() do
      match pictures(index)?
      | (_, let picture: GrayscaleImage val) =>
        let before = originals(index)?
        let after = fingerprint.of(damage(picture)?)?
        changed = changed + before.hamming(after)?
        bits = bits + fingerprint.bits()
      end
      index = index + 1
    end
    if bits == 0 then return 0.0 end
    changed.f64() / bits.f64()

  fun _apart(
    pictures: Array[(String, GrayscaleImage val)] val,
    originals: Array[ImageFingerprint val])
    : F64 ?
  =>
    var changed: USize = 0
    var bits: USize = 0
    var left: USize = 0
    while left < pictures.size() do
      var right: USize = left + 1
      while right < pictures.size() do
        changed = changed + originals(left)?.hamming(originals(right)?)?
        bits = bits + originals(left)?.size()
        right = right + 1
      end
      left = left + 1
    end
    if bits == 0 then return 0.0 end
    changed.f64() / bits.f64()

  fun _share(value: F64): String =>
    let tenths = (value * 1000.0).round().i64()
    let whole = tenths / 10
    (whole.string() + "." + (tenths - (whole * 10)).string()) + "%"

  fun _pad(text: String, width: USize): String =>
    let padded: String iso = recover iso String(width) end
    padded.append(text)
    var added: USize = text.size()
    while added < width do
      padded.append(" ")
      added = added + 1
    end
    consume padded
