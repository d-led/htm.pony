use "../../htm/encoders"
use "../../htm/util"

actor Main
  """
  A scalar encoder turns one number into a fixed-width bit vector.

  The block of set bits slides with the value, so values close together share
  most of their bits and values far apart share few. The last section counts the
  shared bits between neighbouring values to show that.
  """
  new create(env: Env) =>
    try
      let params = ScalarEncoderParams(23, 0, 1 where radius' = 0.5, periodic' = true)
      let encoder = ScalarEncoder(params)?

      env.out.print("values 0 to 1, " + encoder.n.string() + " bits, 23 set per value")
      env.out.print("")

      let values: Array[F64] = [0.50; 0.55; 0.60; 0.65]
      for value in values.values() do
        env.out.print(_pad(value.string(), 7) + _bits(_encode(encoder, value)?))
      end

      env.out.print("")
      env.out.print("bits shared with the next value:")
      for value in values.values() do
        if value < 0.65 then
          let here = _encode(encoder, value)?
          let next = _encode(encoder, value + 0.05)?
          env.out.print(_pad(value.string(), 7) + _shared(here, next).string())
        end
      end

      env.exitcode(0)
    else
      env.out.print("the example failed")
      env.exitcode(1)
    end

  fun _encode(encoder: ScalarEncoder, value: F64): Array[Bool] ? =>
    match encoder.encode(value, false)
    | let bits: Array[Bool] => bits
    else
      error
    end

  fun _bits(values: ReadSeq[Bool]): String =>
    var text: String = ""
    for value in values.values() do
      if value then text = text + "#" else text = text + "." end
    end
    text

  fun _shared(left: ReadSeq[Bool], right: ReadSeq[Bool]): USize =>
    var count: USize = 0
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? and right(index)? then count = count + 1 end
        index = index + 1
      end
    end
    count

  fun _pad(text: String, width: USize): String =>
    var padded: String = text
    while padded.size() < width do
      padded = padded + " "
    end
    padded
