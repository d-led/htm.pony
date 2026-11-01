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
