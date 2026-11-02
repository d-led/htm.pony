use "collections"
use "pony_test"
use "../htm/encoders"

// htm.core's `GridCellEncoder`, whose behavioural tests these follow:
// tests/encoders/grid_cell_test.py. Its golden-bits test pins the cells that
// numpy's random stream happens to pick, which says nothing about the encoding;
// the tests here hold the encoder to how activity relates to distance instead.

class GridCellEncodingTest is TestList
  fun name(): String => "Grid cell encoder"

  fun tag tests(test: PonyTest) =>
    test(_TheSameLocationAndSeedGiveTheSameCells)
    test(_AnotherSeedPutsTheLatticesSomewhereElse)
    test(_AShareOfTheCellsFiresAtALocation)
    test(_NearbyPlacesShareCellsAndDistantOnesDoNot)
    test(_APlaceThatIsNotANumberFiresNothing)

primitive GridCellFixture
  fun periods(): Array[F64] val =>
    recover val [6.0; 8.5; 12.0; 17.0; 24.0] end

  fun encoder(sparsity: F64 = 0.25, seed: U64 = 42): GridCellEncoder ? =>
    GridCellEncoder(200, sparsity, periods(), seed)?

  fun cells(at: GridCellEncoder, x: F64, y: F64): Set[USize] val ? =>
    recover val
      let set = Set[USize]
      for cell in at.encode(x, y)?.values() do
        set.set(cell)
      end
      set
    end

  fun shared(left: Set[USize] val, right: Set[USize] val): F64 =>
    var common: F64 = 0.0
    for cell in left.values() do
      if right.contains(cell) then common = common + 1.0 end
    end
    common / left.size().f64()

class iso _TheSameLocationAndSeedGiveTheSameCells is UnitTest
  fun name(): String => "the same location and seed give the same cells"

  fun apply(h: TestHelper) ? =>
    let once = GridCellFixture.cells(GridCellFixture.encoder()?, 77.0, 88.0)?
    let twice = GridCellFixture.cells(GridCellFixture.encoder()?, 77.0, 88.0)?

    h.assert_true(once == twice, "two encoders with one seed agree")

class iso _AnotherSeedPutsTheLatticesSomewhereElse is UnitTest
  fun name(): String => "another seed puts the lattices somewhere else"

  fun apply(h: TestHelper) ? =>
    let first =
      GridCellFixture.cells(GridCellFixture.encoder(0.25, 42)?, 2.0, 1.333)?
    let other =
      GridCellFixture.cells(GridCellFixture.encoder(0.25, 43)?, 2.0, 1.333)?

    h.assert_true(first != other)

class iso _AShareOfTheCellsFiresAtALocation is UnitTest
  fun name(): String => "a quarter of the cells fire at any location"

  fun apply(h: TestHelper) ? =>
    let encoder = GridCellFixture.encoder(0.25)?
    h.assert_eq[USize](200, encoder.width())
    h.assert_eq[USize](50, encoder.encode(3.0, 4.0)?.size())

    let everywhere = GridCellFixture.encoder(1.0)?
    h.assert_eq[USize](200, everywhere.encode(3.0, 4.0)?.size())

class iso _NearbyPlacesShareCellsAndDistantOnesDoNot is UnitTest
  fun name(): String => "overlap falls as the distance grows"

  fun apply(h: TestHelper) ? =>
    let encoder = GridCellFixture.encoder()?
    let here = GridCellFixture.cells(encoder, 0.0, 0.0)?

    // one unit is a fifth of the shortest period, and three quarters of the
    // cells survive it
    h.assert_true(
      GridCellFixture.shared(here, GridCellFixture.cells(encoder, 1.0, 0.0)?)
        > 0.5,
      "a step of one unit keeps most of the cells")

    // past the shortest period the cells have turned over almost completely.
    // The overlap does not fall monotonically - a periodic code comes back
    // near itself whenever two modules line up again - so what is asserted is
    // the ceiling, not the shape.
    var step: USize = 3
    while step <= 20 do
      let share = GridCellFixture.shared(here,
        GridCellFixture.cells(encoder, step.f64(), 0.0)?)
      h.assert_true(share < 0.4,
        "three or more units away, less than 40% of the cells are shared, at "
          + step.string())
      step = step + 1
    end

    let far = GridCellFixture.cells(encoder, 60.0, 60.0)?
    h.assert_true(GridCellFixture.shared(here, far) < 0.2,
      "a place sixty units away shares little")

class iso _APlaceThatIsNotANumberFiresNothing is UnitTest
  fun name(): String => "a missing coordinate activates nothing"

  fun apply(h: TestHelper) ? =>
    let encoder = GridCellFixture.encoder()?
    let nowhere = F64(0.0) / F64(0.0)
    h.assert_true(nowhere.nan(), "the fixture really is not a number")

    h.assert_eq[USize](0, encoder.encode(3.0, nowhere)?.size())
    h.assert_eq[USize](0, encoder.encode(nowhere, 3.0)?.size())
