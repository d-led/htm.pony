use "../encoders"

class val CorpusImage
  """
  One picture of a corpus: what it is, and its fingerprint.

  The label is whatever the corpus said the picture is - the name of the
  directory it was found in - and is compared as a string, so a corpus does not
  have to number its classes.
  """
  let label: String val
  let fingerprint: ImageFingerprint val

  new val create(label': String val, fingerprint': ImageFingerprint val) =>
    label = label'
    fingerprint = fingerprint'

  fun hamming(that: CorpusImage val): USize ? =>
    """
    How many fingerprint bits the two pictures disagree on.

    Two pictures of the same fingerprint width always compare, so the `?` is
    the fingerprint's rather than this picture's.
    """
    fingerprint.hamming(that.fingerprint)?
