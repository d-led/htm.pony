use "itertools"

primitive BoolArray
  fun from01(i: Array[U8]): Array[Bool] =>
    Iter[U8](i.values())
        .map[Bool]({(x) => x != 0})
        .collect(Array[Bool](i.size()))

  fun are_equal(left: ReadSeq[Bool], right: ReadSeq[Bool]) : Bool =>
    if left.size() != right.size() then
      return false
    end

    try
      var i: USize = 0
      while i < left.size() do
        if left(i)? != right(i)? then
          return false
        end
        i = i + 1
      end
    else
      // "oops"
      return false
    end

    // if all the checks succeed
    true

  fun subset_slice(values: ReadSeq[Bool], indices: ReadSeq[USize]) : Array[Bool] ? =>
    let size = indices.size()
    var result = Array[Bool].init(false, size)

    var i: USize = 0
    while i < size do
      result (i) ? = values(indices(i) ?) ?
      i = i + 1
    end
    
    result

  fun set_value_at_indices(values: Array[Bool] ref, indices: ReadSeq[USize], value: Bool) ? =>
    let size = indices.size()

    var i: USize = 0
    while i < size do
      values ( indices(i) ? ) ? = value
      i = i + 1
    end

  fun set_value_in_range(values: Array[Bool] ref, value: Bool, start: USize, length: USize) ? =>
    var i: USize = 0
    while i < length do
      values ( start + i ) ? = value
      i = i + 1
    end

  fun on_indices(values: ReadSeq[Bool]) : Array[USize] =>
    Iter[Bool](values.values())
      .enum()
      .filter_map[USize]({
        (t: (USize, Bool)) : (USize | None) => if t._2 then t._1 end 
      })
      .collect(Array[USize](values.size()))
