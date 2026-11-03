use "pony_test"
use "files"

use "../htm/measure"

primitive CorpusFixture
  """
  A corpus directory written for one test, and taken away afterwards.

  The pictures are copies of the PNG that `stb_decoder_test` decodes, so a
  corpus here is real data read through the real decoder rather than a stub.
  """
  fun picture(h: TestHelper): Array[U8] val =>
    let path = FilePath(FileAuth(h.env.root), "fixtures/pattern.png")
    let file = File(path)
    file.read(file.size())

  fun make(
    h: TestHelper,
    labels: Array[String val] val,
    pictures: USize)
    : FilePath val ?
  =>
    """
    One directory per label, each holding `pictures` copies of the picture.
    """
    let root: FilePath val = FilePath.mkdtemp(FileAuth(h.env.root), "corpus")?
    for label in labels.values() do
      let class_dir: FilePath val = root.join(label)?
      if not class_dir.mkdir(true) then error end
      var written: USize = 0
      while written < pictures do
        write(
          class_dir.join(label + "-" + written.string() + ".png")?,
          picture(h))?
        written = written + 1
      end
    end
    root

  fun write(path: FilePath val, bytes: (Array[U8] val | String)) ? =>
    match CreateFile(path)
    | let file: File => if not file.write(bytes) then error end
    else error
    end

  fun dispose(path: FilePath val) =>
    try
      with directory = Directory(path)? do
        for entry in directory.entries()?.values() do
          let child: FilePath val = path.join(entry)?
          _clear(child)
          child.remove()
        end
      end
      path.remove()
    end

  fun _clear(path: FilePath val) =>
    """
    Empty a directory so it can be removed, or do nothing to a file.
    """
    try
      with directory = Directory(path)? do
        for entry in directory.entries()?.values() do
          path.join(entry)?.remove()
        end
      end
    end

class ImageCorpusTest is TestList
  fun name(): String => "Picture corpus"

  fun tag tests(test: PonyTest) =>
    test(_ACorpusLabelsItsPicturesByTheirDirectory)
    test(_AFileThatIsNotAPictureIsNotCounted)
    test(_APictureThatWillNotDecodeIsRefused)
    test(_OnlyThePicturesAskedForAreTaken)
    test(_AFolderWithNoPicturesIsRefused)
    test(_AMissingFolderIsNotAFolder)

class iso _ACorpusLabelsItsPicturesByTheirDirectory is UnitTest
  fun name(): String =>
    "corpus: every picture is labelled by the directory it was found in"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = ["cat"; "dog"]
    let root = CorpusFixture.make(h, labels, 2)?
    match ImageCorpus.load(root, 10)
    | let corpus: Corpus val =>
      h.assert_eq[USize](4, corpus.size())
      h.assert_eq[USize](2, corpus.class_count())
      h.assert_eq[USize](0, corpus.refused)
    | NotAFolder => h.fail("the corpus directory was not read as a directory")
    | NoPictures => h.fail("no picture was found where two were written")
    end
    CorpusFixture.dispose(root)

class iso _AFileThatIsNotAPictureIsNotCounted is UnitTest
  fun name(): String => "corpus: a file that is not a picture is left alone"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = ["cat"]
    let root = CorpusFixture.make(h, labels, 1)?
    CorpusFixture.write(root.join("cat")?.join("notes.txt")?, "not a picture")?
    match ImageCorpus.load(root, 10)
    | let corpus: Corpus val =>
      h.assert_eq[USize](1, corpus.size())
      h.assert_eq[USize](0, corpus.refused)
    | NotAFolder => h.fail("the corpus directory was not read as a directory")
    | NoPictures => h.fail("the one picture was not found")
    end
    CorpusFixture.dispose(root)

class iso _APictureThatWillNotDecodeIsRefused is UnitTest
  fun name(): String => "corpus: a picture that will not decode is refused, not fatal"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = ["cat"]
    let root = CorpusFixture.make(h, labels, 1)?
    CorpusFixture.write(root.join("cat")?.join("broken.png")?, "not a png")?
    match ImageCorpus.load(root, 10)
    | let corpus: Corpus val =>
      h.assert_eq[USize](1, corpus.size())
      h.assert_eq[USize](1, corpus.refused)
    | NotAFolder => h.fail("the corpus directory was not read as a directory")
    | NoPictures => h.fail("the readable picture was lost")
    end
    CorpusFixture.dispose(root)

class iso _OnlyThePicturesAskedForAreTaken is UnitTest
  fun name(): String => "corpus: a class gives at most the pictures asked for"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = ["cat"]
    let root = CorpusFixture.make(h, labels, 3)?
    match ImageCorpus.load(root, 2)
    | let corpus: Corpus val => h.assert_eq[USize](2, corpus.size())
    | NotAFolder => h.fail("the corpus directory was not read as a directory")
    | NoPictures => h.fail("no picture was found")
    end
    CorpusFixture.dispose(root)

class iso _AFolderWithNoPicturesIsRefused is UnitTest
  fun name(): String => "corpus: a directory of no class directories is refused"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = []
    let root = CorpusFixture.make(h, labels, 0)?
    match ImageCorpus.load(root, 10)
    | let corpus: Corpus val =>
      h.fail("a corpus of " + corpus.size().string() + " pictures was read")
    | NotAFolder => h.fail("the empty directory was not read as a directory")
    | NoPictures => h.assert_true(true)
    end
    CorpusFixture.dispose(root)

class iso _AMissingFolderIsNotAFolder is UnitTest
  fun name(): String => "corpus: a path that is not there is not a folder"
  fun apply(h: TestHelper) ? =>
    let labels: Array[String val] val = []
    let root = CorpusFixture.make(h, labels, 0)?
    match ImageCorpus.load(root.join("gone")?, 10)
    | let corpus: Corpus val =>
      h.fail("a corpus of " + corpus.size().string() + " pictures was read")
    | NotAFolder => h.assert_true(true)
    | NoPictures => h.fail("a missing directory was read as an empty one")
    end
    CorpusFixture.dispose(root)
