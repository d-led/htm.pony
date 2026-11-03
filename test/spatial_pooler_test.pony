// Follows spatialPooler_test.go in htm-community/htm (MIT): the assertions are
// that repository's, the calls go through this repository's vocabulary.
use "pony_test"
use "../htm"

// The Go reference: spatialPooler.mapPotential, initPermanence and Compute.

class SpatialPoolerTest is TestList
  fun name(): String => "Spatial pooler"

  fun tag tests(test: PonyTest) =>
    test(_TheSameSeedWiresTheSamePooler)
    test(_EveryColumnReachesInputThatExists)
    test(_AnInputNothingMatchesActivatesNothing)
    test(_ARepresentationIsSparserThanTheInput)

  fun config(): SpatialPoolerConfig =>
    SpatialPoolerConfig([8; 8], [64]
      where global_inhibition' = false, num_active_columns_per_inh_area' = 2.0)

  fun input(on: ReadSeq[USize], width: USize = 64): Array[Bool] =>
    let values = Array[Bool].init(false, width)
    try
      for index in on.values() do
        values(index)? = true
      end
    end
    values

class iso _TheSameSeedWiresTheSamePooler is UnitTest
  fun name(): String => "the same seed produces the same representation"

  fun apply(h: TestHelper) ? =>
    let first = SpatialPooler(SpatialPoolerTest.config(), 7)?
    let second = SpatialPooler(SpatialPoolerTest.config(), 7)?
    let input = SpatialPoolerTest.input([3; 5; 8; 13; 21])

    let first_answer = first.compute(input)?
    h.assert_array_eq[USize](first_answer, second.compute(input)?)
    h.assert_true(first_answer.size() > 0, "the representation should not be empty")

class iso _EveryColumnReachesInputThatExists is UnitTest
  fun name(): String => "no column is wired to an input that does not exist"

  fun apply(h: TestHelper) ? =>
    let pooler = SpatialPooler(SpatialPoolerTest.config(), 3)?

    for column in pooler.columns.values() do
      h.assert_true(column.synapses.size() > 0, "a column should have synapses")
      for synapse in column.synapses.values() do
        h.assert_true(synapse.input < 64, "input " + synapse.input.string() + " is outside the input")
      end
    end

class iso _AnInputNothingMatchesActivatesNothing is UnitTest
  fun name(): String => "an input that no column matches activates no column"

  fun apply(h: TestHelper) ? =>
    let pooler = SpatialPooler(SpatialPoolerTest.config(), 11)?

    h.assert_eq[USize](0, pooler.compute(SpatialPoolerTest.input([]))?.size())

class iso _ARepresentationIsSparserThanTheInput is UnitTest
  fun name(): String => "the representation is far smaller than the population"

  fun apply(h: TestHelper) ? =>
    let pooler = SpatialPooler(SpatialPoolerTest.config(), 5)?
    let active = pooler.compute(SpatialPoolerTest.input([1; 2; 4; 8; 16; 32]))?

    h.assert_true(active.size() > 0, "something should be represented")
    h.assert_true(active.size() < pooler.size(), "the representation cannot be the whole population")
