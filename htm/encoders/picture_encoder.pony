use "./stb"

interface PictureSink
  """
  Whoever asked for a picture to be turned into bits.

  Both methods are the whole answer: a picture that decoded, with the
  fingerprint it has and the representation it makes, or a refusal for bytes
  that are not a picture or a picture too large to make.
  """
  be pictured(fingerprint: ImageFingerprint val, bits: Array[Bool] val)
  be refused()

actor PictureEncoder is PictureSink
  """
  One picture at a time, in an actor rather than on whoever is holding the file.

  The work is decode, fingerprint, encode, and the decode is the one call in
  this library that is not Pony: `stb_image` runs inside C on the thread that
  asked and cannot be interrupted. Here that thread belongs to this actor, so the
  caller goes on while the picture is being read, and the answer arrives as a
  message - which is the same shape as the rest of the library, where nothing
  returns a value and everything pushes forward.

  One of these is the minimum; more of them is the fan-out. They are not sized
  to scheduler threads - Pony multiplexes many actors onto a thread and the
  runtime decides who runs where - so the number to build is the number of
  pictures that may be in flight at once. Each one that is decoding occupies a
  thread inside C while it does, which is the limit worth knowing: N decoders
  need N threads to be N at a time.

  It is also a `PictureSink`, so an encoder can push to another encoder: the
  answers come back to whoever asked, and a coordinator that spreads work over
  several encoders collects them without knowing how many there are.
  """
  let _encoder: ImageEncoder val

  new create(encoder: ImageEncoder val) =>
    _encoder = encoder

  be picture(bytes: Array[U8] val, asker: PictureSink tag) =>
    """
    Turn one picture into bits, or say that it will not be turned into any.
    """
    match StbDecoder.decode(bytes)
    | let image: GrayscaleImage val =>
      try
        let fingerprint = DifferenceHash.compute(image)?
        asker.pictured(fingerprint, _frozen(_encoder.encode_fingerprint(fingerprint)?))
      else
        asker.refused()
      end
    | DecodeFailed => asker.refused()
    end

  be pictured(fingerprint: ImageFingerprint val, bits: Array[Bool] val) =>
    """
    A picture that came from another encoder has already been encoded; passing it
    on unchanged keeps this actor usable as one stage of a chain.
    """
    None

  be refused() => None

  fun _frozen(bits: Array[Bool]): Array[Bool] val =>
    let copy: Array[Bool] iso = recover iso Array[Bool] end
    for bit in bits.values() do
      copy.push(bit)
    end
    consume copy
