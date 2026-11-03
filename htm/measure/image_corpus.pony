use "collections"
use "files"

use "../encoders"
use "../encoders/stb"

primitive ImageCorpus
  """
  Reads a corpus of pictures off a disk: one directory per class, pictures
  inside.

  The directory a picture was found in is its label, so a corpus labels itself
  by the way it is filed. Nothing is pulled out of a picture file's name, and
  nothing is assumed about how many classes there are.

  Every class contributes at most `per_class` pictures, taken in name order, and
  every class is read in name order, so the same directory always gives the same
  corpus. That is what makes a measurement over it worth printing: the numbers
  are the corpus's, not the filesystem's.
  """

  fun load(
    root: FilePath val,
    per_class: USize)
    : (Corpus val | NotAFolder | NoPictures)
  =>
    """
    Every picture of every class directory under `root`, up to `per_class` of
    each.

    A picture that will not decode, or that is too small to fingerprint, is
    counted in `refused` rather than ending the run: a corpus is real data, and
    one unreadable file in it is not a reason to measure nothing.
    """
    if not _is_folder(root) then return NotAFolder end
    let pictures: Array[CorpusImage val] iso =
      recover iso Array[CorpusImage val] end
    var refused: USize = 0
    for entry in _entries(root).values() do
      match _load_class(root, entry, per_class)
      | (let loaded: Array[CorpusImage val] ref, let refused_here: USize) =>
        for picture in loaded.values() do
          pictures.push(picture)
        end
        refused = refused + refused_here
      end
    end
    if pictures.size() == 0 then return NoPictures end
    Corpus(consume pictures, refused)

  fun _entries(root: FilePath val): Array[String val] val =>
    """
    The names in a directory, in name order.

    A directory that cannot be listed is read as an empty one: the caller then
    hears `NoPictures`, which is the same answer a corpus that holds none
    deserves.
    """
    try
      with directory = Directory(root)? do
        let entries: Array[String] ref = directory.entries()?
        Sort[Array[String], String](entries)
        let sorted: Array[String val] iso =
          recover iso Array[String val](entries.size()) end
        for name in entries.values() do
          sorted.push(recover val name end)
        end
        consume sorted
      end
    else
      recover val Array[String val] end
    end

  fun _load_class(
    root: FilePath val,
    name: String val,
    per_class: USize)
    : (Array[CorpusImage val] ref, USize)
  =>
    """
    One class directory: up to `per_class` fingerprinted pictures, and how many
    pictures in it would not load.

    A class directory that cannot be read gives nothing rather than ending the
    corpus, so one unreadable directory costs its own pictures and no others'.
    """
    let empty: Array[CorpusImage val] = Array[CorpusImage val]
    try
      let class_dir: FilePath val = root.join(name)?
      if not _is_folder(class_dir) then return (empty, 0) end
      let label: String val = recover val Path.base(class_dir.path, false) end
      let pictures: Array[CorpusImage val] = Array[CorpusImage val]
      var refused: USize = 0
      for picture_name in _names(class_dir, per_class)?.values() do
        match _fingerprint(class_dir, picture_name)
        | let fingerprint: ImageFingerprint val =>
          pictures.push(CorpusImage(label, fingerprint))
        | DecodeFailed =>
          refused = refused + 1
        end
      end
      (pictures, refused)
    else
      (empty, 0)
    end

  fun _names(class_dir: FilePath val, limit: USize): Array[String val] val ? =>
    let names: Array[String val] = Array[String val]
    with directory = Directory(class_dir)? do
      let entries: Array[String] ref = directory.entries()?
      for entry in entries.values() do
        let child: FilePath val = class_dir.join(entry)?
        if not _is_folder(child) and _is_picture(entry) then
          names.push(recover val entry end)
        end
      end
    end
    Sort[Array[String val], String](names)
    let kept: Array[String val] iso = recover iso Array[String val](limit) end
    for (index, name) in names.pairs() do
      if index < limit then kept.push(name) end
    end
    consume kept

  fun _fingerprint(
    class_dir: FilePath val,
    name: String val)
    : (ImageFingerprint val | DecodeFailed)
  =>
    try
      let file = File(class_dir.join(name)?)
      let bytes: Array[U8] val = file.read(file.size())
      match StbDecoder.decode(bytes)
      | let image: GrayscaleImage val => DifferenceHash.compute(image)?
      | DecodeFailed => DecodeFailed
      end
    else
      DecodeFailed
    end

  fun _is_picture(name: String): Bool =>
    """
    Whether a file name carries an extension the decoder knows.

    `Array.contains` compares by identity, so the comparison is spelled out: a
    name read off a directory is a different `String` from the one in the list
    even when it says the same thing.
    """
    let known: Array[String val] val = ["jpeg"; "jpg"; "png"; "bmp"; "gif"]
    let extension: String = Path.ext(name).lower()
    known.contains(extension, {(met: String box, seen: String box): Bool =>
      met == seen })

  fun _is_folder(path: FilePath val): Bool =>
    try FileInfo(path)?.directory else false end
