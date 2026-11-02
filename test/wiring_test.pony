use "random"
use "pony_test"
use "../htm"

// The Go reference: spatialPooler.mapPotential, which decides which inputs a
// column may reach before anything has been learned, and spatialPooler.initPermanence,
// which decides how strongly it believes in them at that point.

class WiringTest is TestList
  fun name(): String => "Wiring"

  fun tag tests(test: PonyTest) =>
    test(_AColumnReachesTheInputAroundItsOwnPosition)
    test(_AColumnConnectsToOneShareOfThatReach)
    test(_AFreshColumnStartsJustEitherSideOfTheThreshold)

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

class iso _AFreshColumnStartsJustEitherSideOfTheThreshold is UnitTest
  fun name(): String => "a fresh column starts its beliefs either side of the threshold"

  fun apply(h: TestHelper) ? =>
    // the reference's initPermanence: half of the connections start a little
    // above the threshold, so a little learning can undo them, and half a little
    // below it, so only learning can make them count
    let config = Pool.config()
    let inputs = Grid([10])?
    let random = Rand(11)

    // no fresh connection is stronger than the threshold plus a quarter step
    let ceiling = config.connection_threshold + (config.permanence_increment / 4.0)

    var counting: USize = 0
    var total: USize = 0

    var column: USize = 0
    while column < 4 do
      for synapse in Wiring.synapses(config, inputs, random, column)?.values() do
        h.assert_true(synapse.permanence <= ceiling,
          "a belief stronger than the wiring hands out")

        if synapse.connected(config.connection_threshold) then
          counting = counting + 1
        end
        total = total + 1
      end
      column = column + 1
    end

    h.assert_true(total > 0, "the columns should have connections")

    let share = counting.f64() / total.f64()
    h.assert_true((share > 0.25) and (share < 0.75),
      "about half should count, got " + share.string())
