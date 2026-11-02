use "random"
use "pony_test"
use "../htm"

// The Go reference: spatialPooler.mapPotential, which decides which inputs a
// column may reach before anything has been learned.

class WiringTest is TestList
  fun name(): String => "Wiring"

  fun tag tests(test: PonyTest) =>
    test(_AColumnReachesTheInputAroundItsOwnPosition)
    test(_AColumnConnectsToOneShareOfThatReach)

primitive Pool
  """
  Ten inputs, four columns, and a column that may reach two inputs either side of
  where it sits in the input.
  """
  fun config(potential_pct: F64 = 1.0): SpatialPoolerConfig val =>
    SpatialPoolerConfig([4], [10], false, 2.0, -1.0, 2, potential_pct)

class iso _AColumnReachesTheInputAroundItsOwnPosition is UnitTest
  fun name(): String => "a column reaches the inputs around where it sits"

  fun apply(h: TestHelper) ? =>
    let inputs = Grid([10])?
    let config = Pool.config()

    // the first column sits at the start, so the input is cut off there
    h.assert_array_eq[USize]([0; 1; 2],
      Wiring.receptive_field(config, inputs, 0), "the first column")

    // the third sits at two thirds of the way across
    h.assert_array_eq[USize]([4; 5; 6; 7; 8],
      Wiring.receptive_field(config, inputs, 2), "the third column")

    // and the last one runs off the end the same way the first ran off the start
    h.assert_array_eq[USize]([7; 8; 9],
      Wiring.receptive_field(config, inputs, 3), "the last column")

class iso _AColumnConnectsToOneShareOfThatReach is UnitTest
  fun name(): String => "a column connects to a share of what it can reach"

  fun apply(h: TestHelper) ? =>
    let inputs = Grid([10])?

    // half of a five input reach is three inputs, and they are inside the reach
    let wired = Wiring.synapses(Pool.config(0.5), inputs, Rand(7), 2)?

    h.assert_eq[USize](3, wired.size(), "half of five inputs")
    for synapse in wired.values() do
      h.assert_true((synapse.input >= 4) and (synapse.input <= 8),
        "a synapse outside the column's reach")
      h.assert_true((synapse.permanence > 0.0) and (synapse.permanence <= 1.0),
        "a permanence outside nought and one")
    end
