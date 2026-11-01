use "collections"

primitive Dimensions
  """
  Small operations on dimension lists, used before an object that owns them
  exists - constructors get a `tag` receiver and cannot call their own methods.
  """

  fun product(dims: ReadSeq[USize]): USize =>
    """
    How many cells the dimensions describe.
    """
    var result: USize = 1
    for dimension in dims.values() do
      result = result * dimension
    end
    result

  fun frozen(dims: ReadSeq[USize]): Array[USize] val =>
    """
    A shareable copy, so a caller cannot change a shape after it is in use.
    """
    let copy = recover trn Array[USize](dims.size()) end
    for dimension in dims.values() do
      copy.push(dimension)
    end
    consume copy
