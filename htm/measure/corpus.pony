use "collections"

use "../encoders"

primitive NotAFolder
  """
  The path a corpus was asked of is missing, or is not a directory.
  """

primitive NoPictures
  """
  The directory held no class directory with a usable picture in it.

  A corpus of one empty directory per class is not an error to be worked
  around: it is a path that points somewhere else than the reader thought.
  """

class val Corpus
  """
  What a corpus directory held: the pictures that loaded, and how many did not.

  Nothing here is ordered by anything but the corpus itself - class directories
  and picture names are read in name order - so the same directory always gives
  the same corpus, and a measurement taken over it can be repeated.
  """
  let pictures: Array[CorpusImage val] val
  let refused: USize

  new val create(pictures': Array[CorpusImage val] val, refused': USize) =>
    pictures = pictures'
    refused = refused'

  fun size(): USize => pictures.size()

  fun class_count(): USize =>
    """
    How many distinct labels the pictures carry.

    A count rather than a list: what a measurement needs to know is how many
    kinds of thing it was asked to tell apart, and a list of directory names
    would only be printed.
    """
    let seen: Set[String val] = Set[String val]
    for picture in pictures.values() do
      seen.set(picture.label)
    end
    seen.size()
