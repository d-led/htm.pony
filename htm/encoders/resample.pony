use "collections"

primitive Resample
  """
  A picture read as a fixed grid of brightness values, whatever its size.

  Each cell of the grid is the average of the pixels it covers, which is what
  makes a picture and a copy of it twice as wide read the same: averaging
  forgets where inside the cell a bright speck was.

  A grid finer than the picture - an 18 by 16 picture asked for 64 by 64 - has
  cells that cover no pixel at all, and those take the nearest pixel instead of
  an average. That is a stretch rather than a reading, and it is the only thing
  a small picture can give: which pixel is nearest is a fact about the picture,
  and an average of no pixels is not.
  """

  fun block_average(
    image: GrayscaleImage val,
    columns: USize,
    rows: USize)
    : Array[F64] ?
  =>
    """
    The picture as `columns` by `rows` brightness values, row by row.
    """
    if (columns == 0) or (rows == 0) then error end

    let result = Array[F64](columns * rows)
    var row: USize = 0
    while row < rows do
      var column: USize = 0
      while column < columns do
        result.push(_cell(image, column, row, columns, rows)?)
        column = column + 1
      end
      row = row + 1
    end
    result

  fun _cell(
    image: GrayscaleImage val,
    column: USize,
    row: USize,
    columns: USize,
    rows: USize)
    : F64 ?
  =>
    let left = (column * image.width) / columns
    let right = ((column + 1) * image.width) / columns
    let top = (row * image.height) / rows
    let bottom = ((row + 1) * image.height) / rows

    if (right > left) and (bottom > top) then
      _average(image, left, top, right, bottom)?
    else
      _nearest(image, left, top)?
    end

  fun _average(
    image: GrayscaleImage val,
    left: USize,
    top: USize,
    right: USize,
    bottom: USize)
    : F64 ?
  =>
    var total: USize = 0
    var count: USize = 0

    var y = top
    while y < bottom do
      var x = left
      while x < right do
        total = total + image(x, y)?.usize()
        count = count + 1
        x = x + 1
      end
      y = y + 1
    end

    if count == 0 then return 0.0 end
    total.f64() / count.f64()

  fun _nearest(image: GrayscaleImage val, x: USize, y: USize): F64 ? =>
    image(_within(x, image.width), _within(y, image.height))?.f64()

  fun _within(index: USize, size: USize): USize =>
    """
    The index inside a picture of that size: a cell that starts past the last
    pixel reads the last pixel.
    """
    if index < size then index else size - 1 end
