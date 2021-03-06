use "debug"

class NoOpScalarEncoder
    fun noop(): Bool => true

    // throws for now
    fun encode(input: F64, learn_unused: Bool) : (Array[Bool] | EncodingFailed) =>
        Debug.err("NoOpScalarEncoder encode failed deliberately: it should not be used")
        EncodingFailed

    fun encode_at_pos(input: F64, learn_unused: Bool, output: Array[Bool] ref, pos: USize): (None | EncodingFailed) => if false then EncodingFailed end
