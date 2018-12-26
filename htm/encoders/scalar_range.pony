class val ScalarRange
    let left: F64
    let right: F64

    new val create(left': F64, right': F64) =>
        left = left'
        right = right'

    fun box eq(that: box->ScalarRange) : Bool =>
        (left == that.left) and (right == that.right)

    fun box ne(that: box->ScalarRange) : Bool =>
        not eq(that)

    fun box string(): String iso^ => 
        (
            "["
            + left.string()
            + ", ".string()
            + right.string()
            + "]"
        ).string()
