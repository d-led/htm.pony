interface SomeScalarEncoder
    // indicates, whether the encoder is a no-op encoder,
    // in order to have parts of the vector not encoded, but retaining width
    fun noop(): Bool

    fun encode(input: F64, learn_unused: Bool) : Array[Bool] ?
    fun encode_at_pos(input: F64, learn_unused: Bool, output: Array[Bool] ref, pos: USize) ?