use "pony_test"
use "../htm"

// The Go reference: spatialPooler.InhibitColumns, the density calculation.

class SpatialPoolerConfigTest is TestList
  fun name(): String => "Spatial pooler config"

  fun tag tests(test: PonyTest) =>
    test(_DimensionsDecideThePopulation)
    test(_ARequestedCountBecomesAFractionOfAnArea)
    test(_TheAreaNeverExceedsTheColumnsThatExist)
    test(_AStatedDensityWins)
    test(_TheDensityIsCappedAtOneHalf)

class iso _DimensionsDecideThePopulation is UnitTest
  fun name(): String => "the grid dimensions decide how many columns and inputs there are"

  fun apply(h: TestHelper) =>
    let config = SpatialPoolerConfig([8; 4], [32; 32])
    h.assert_eq[USize](32, config.num_columns())
    h.assert_eq[USize](1024, config.num_inputs())

class iso _ARequestedCountBecomesAFractionOfAnArea is UnitTest
  fun name(): String => "a requested count becomes a fraction of one inhibition area"

  fun apply(h: TestHelper) =>
    // one dimension, radius 1 -> three columns per area
    let config = SpatialPoolerConfig([8], [8], false, 1.0)
    h.assert_eq[F64](1.0 / 3.0, config.density(1))

class iso _TheAreaNeverExceedsTheColumnsThatExist is UnitTest
  fun name(): String => "an area is never larger than the grid"

  fun apply(h: TestHelper) =>
    // a wide radius would cover eleven columns, but only one exists
    let config = SpatialPoolerConfig([1], [1], false, 0.2)
    h.assert_eq[F64](0.2, config.density(5))

class iso _AStatedDensityWins is UnitTest
  fun name(): String => "a stated local area density is used as it stands"

  fun apply(h: TestHelper) =>
    let config = SpatialPoolerConfig([8], [8], false, 10.0, 0.125)
    h.assert_eq[F64](0.125, config.density(1))

class iso _TheDensityIsCappedAtOneHalf is UnitTest
  fun name(): String => "no area may ask for more than half its columns"

  fun apply(h: TestHelper) =>
    // ten winners out of an area of three would be absurd
    let config = SpatialPoolerConfig([8], [8], false, 10.0)
    h.assert_eq[F64](0.5, config.density(1))
