class NoOpScalarEncoder
    fun noop(): Bool => true

    // throws for now
    fun encode(input: F64, learn_unused: Bool) : Array[Bool] ? => error
    
    fun encode_at_pos(input: F64, learn_unused: Bool, output: Array[Bool] ref, pos: USize) ? => if false then error end
