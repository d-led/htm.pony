use "itertools"

primitive BoolArray
  fun from01(i: Array[U8]): Array[Bool] =>
    Iter[U8](i.values())
        .map[Bool]({(x) => x != 0})
        .collect(Array[Bool](i.size()))
