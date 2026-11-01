use "pony_test"
use "collections"
use "../htm"

// The Go reference: spatialPooler.getNeighborsND and utils' index arithmetic.

class TopologyTest is TestList
  fun name(): String => "Topology"

  fun tag tests(test: PonyTest) =>
    test(_GridSize)
    test(_FlatIndexRoundTrip)
    test(_InteriorCellIsSurrounded)
    test(_BorderCellSeesOnlyCellsThatExist)
    test(_WrappedBorderCellMeetsTheOppositeEdge)
    test(_NeighbourhoodExcludesTheCellItself)
    test(_LargeRadiusDoesNotRepeatNeighbours)
    test(_EmptyNeighbourhoodForRadiusZero)
    test(_GridRejectsDegenerateDimensions)

primitive Neighbourhood
  """
  Neighbours are a set; the order they are found in is not part of the contract.
  """
  fun assert_is(h: TestHelper, expected: ReadSeq[USize], actual: ReadSeq[USize]) =>
    let wanted = Set[USize]
    for cell in expected.values() do wanted.set(cell) end

    h.assert_eq[USize](wanted.size(), actual.size(),
      "expected " + wanted.size().string() + " neighbours, got " + actual.size().string())

    for cell in actual.values() do
      h.assert_true(wanted.contains(cell), "unexpected neighbour " + cell.string())
    end

class iso _GridSize is UnitTest
  fun name(): String => "a grid knows how many cells it holds"

  fun apply(h: TestHelper) =>
    try
      h.assert_eq[USize](6, Grid([2; 3])?.size)
      h.assert_eq[USize](1, Grid([1])?.size)
    else
      h.fail("a grid of positive dimensions should be constructible")
    end

class iso _FlatIndexRoundTrip is UnitTest
  fun name(): String => "a flat index maps to its coordinates and back"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([2; 3])?
      h.assert_array_eq[USize]([1; 2], grid.coords(5)?)
      h.assert_eq[USize](5, grid.flatten([1; 2])?)
    else
      h.fail("index and coordinates should survive a round trip")
    end

class iso _InteriorCellIsSurrounded is UnitTest
  fun name(): String => "a cell in the middle of a grid is surrounded on all sides"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([3; 3])?
      Neighbourhood.assert_is(h, [0; 1; 2; 3; 5; 6; 7; 8], grid.neighbours(4, 1, false)?)
    else
      h.fail("the centre cell should have neighbours")
    end

class iso _BorderCellSeesOnlyCellsThatExist is UnitTest
  fun name(): String => "a corner cell has only the neighbours the grid can hold"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([3; 3])?
      Neighbourhood.assert_is(h, [1; 3; 4], grid.neighbours(0, 1, false)?)
    else
      h.fail("a corner should have neighbours")
    end

class iso _WrappedBorderCellMeetsTheOppositeEdge is UnitTest
  fun name(): String => "a corner cell reaches the opposite corner when the grid wraps"

  fun apply(h: TestHelper) =>
    try
      // a 3x3 grid one step wide reaches every cell from every cell
      let grid = Grid([3; 3])?
      Neighbourhood.assert_is(h, [1; 2; 3; 4; 5; 6; 7; 8], grid.neighbours(0, 1, true)?)
    else
      h.fail("a wrapping corner should have neighbours")
    end

class iso _NeighbourhoodExcludesTheCellItself is UnitTest
  fun name(): String => "a cell is never its own neighbour"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([4])?
      let neighbours = grid.neighbours(2, 1, true)?
      h.assert_false(neighbours.contains(2), "the cell itself must be excluded")
    else
      h.fail("a cell in a line should have neighbours")
    end

class iso _LargeRadiusDoesNotRepeatNeighbours is UnitTest
  fun name(): String => "a radius wider than the grid visits each other cell once"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([3])?
      Neighbourhood.assert_is(h, [0; 1], grid.neighbours(2, 5, true)?)
    else
      h.fail("a wide radius should be handled")
    end

class iso _EmptyNeighbourhoodForRadiusZero is UnitTest
  fun name(): String => "a radius of zero leaves a cell with no neighbours"

  fun apply(h: TestHelper) =>
    try
      let grid = Grid([3; 3])?
      h.assert_eq[USize](0, grid.neighbours(4, 0, true)?.size())
    else
      h.fail("a zero radius should be handled")
    end

class iso _GridRejectsDegenerateDimensions is UnitTest
  fun name(): String => "a grid needs at least one cell"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => Grid([])? })
    h.assert_error({() ? => Grid([3; 0])? })
