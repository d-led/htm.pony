use "pony_test"
use "../htm"

// The Go reference: spatialPooler.calculateOverlap, over connected synapses.

class ColumnTest is TestList
  fun name(): String => "Column"

  fun tag tests(test: PonyTest) =>
    test(_SilentColumnHasNoOverlap)
    test(_OverlapCountsTheActiveInputsItIsConnectedTo)
    test(_WeakSynapsesDoNotCount)
    test(_InactiveInputNeverCounts)
    test(_SynapseOutsideTheInputIsAWiringError)

primitive Synapses
  """
  A synapse strong enough to count, and one too weak to.
  """
  fun solid(input: USize): Synapse => Synapse(input, 0.5)
  fun weak(input: USize): Synapse => Synapse(input, 0.01)

  fun threshold(): F64 => 0.2

class iso _SilentColumnHasNoOverlap is UnitTest
  fun name(): String => "a column sees nothing when no input is active"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapses.solid(0); Synapses.solid(1)])
    h.assert_eq[USize](0, column.overlap([false; false], Synapses.threshold())?)

class iso _OverlapCountsTheActiveInputsItIsConnectedTo is UnitTest
  fun name(): String => "a column's overlap is the active inputs it is connected to"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapses.solid(0); Synapses.solid(1); Synapses.solid(2)])

    // three connections, two of their inputs on
    h.assert_eq[USize](2, column.overlap([true; false; true], Synapses.threshold())?)

class iso _WeakSynapsesDoNotCount is UnitTest
  fun name(): String => "a synapse below the connection threshold does not count"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapses.solid(0); Synapses.weak(1)])

    // the input is on, but the connection to it is too weak to claim it
    h.assert_eq[USize](1, column.overlap([true; true], Synapses.threshold())?)

class iso _InactiveInputNeverCounts is UnitTest
  fun name(): String => "an inactive input never counts, however strong the synapse"

  fun apply(h: TestHelper) ? =>
    let column = Column([Synapses.solid(0)])

    h.assert_eq[USize](0, column.overlap([false], Synapses.threshold())?)

class iso _SynapseOutsideTheInputIsAWiringError is UnitTest
  fun name(): String => "a synapse reaching outside the input is a wiring error"

  fun apply(h: TestHelper) =>
    let column = Column([Synapses.solid(0); Synapses.solid(5)])

    h.assert_error({() ? => column.overlap([true; true], Synapses.threshold())? })
