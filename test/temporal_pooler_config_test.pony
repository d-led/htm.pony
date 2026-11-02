use "pony_test"
use "../htm"

// The Go reference: temporalPooler.NewTemporalPoolerParams, and the checks
// NewTemporalPooler makes before it builds anything.

class TemporalPoolerConfigTest is TestList
  fun name(): String => "CLA temporal pooler config"

  fun tag tests(test: PonyTest) =>
    test(_ACellIsNamedByItsNodeAndItsOffset)
    test(_WithoutPoolingAnUpdateDoesNotOutliveItsStep)
    test(_APoolerWithoutNodesIsRefused)
    test(_APoolerWithoutCellsInANodeIsRefused)
    test(_APamLengthOfZeroIsRefused)
    test(_FixedSizeNeedsBothLimits)
    test(_FixedSizeRefusesAGlobalDecay)
    test(_FixedSizeRefusesAnAgeLimit)
    test(_FixedSizeRefusesFewerSynapsesThanASegmentWants)
    test(_FixedSizeWithConsistentLimitsIsAccepted)

primitive FixedSize
  """
  A pooler that recycles rather than grows: four segments to a cell, twenty
  synapses to a segment, and nothing that takes a synapse away again.

  Spelled out in full, with the positions named, because the reference's rules
  are about how the parameters relate to each other.
  """
  fun config(decay: F64 = 0.0, age: USize = 0, synapses: USize = 20): TemporalPoolerConfig ? =>
    TemporalPoolerConfig(
      4, 3,                // nodes, and cells in each
      12, 8, 15,           // activation threshold, min threshold, synapses wanted
      false,               // no pooling
      0.11, 0.5,           // initial and connection permanence
      0.1, 0.1, 1.0,       // permanence increment, decrement, ceiling
      decay,               // global decay
      5, 1, 10, 5,         // update window, pam length, the two backtracks
      age,                 // age limit
      32,                  // longest sequence worth naming
      4, synapses)?

class iso _ACellIsNamedByItsNodeAndItsOffset is UnitTest
  fun name(): String => "a cell is named by its node and its position in it"

  fun apply(h: TestHelper) ? =>
    let config = TemporalPoolerConfig(4, 3)?
    h.assert_eq[USize](12, config.cells())
    h.assert_eq[USize](5, config.cell_of(1, 2))
    h.assert_eq[USize](1, config.node_of(5))
    h.assert_eq[USize](2, config.offset_of(5))

class iso _WithoutPoolingAnUpdateDoesNotOutliveItsStep is UnitTest
  fun name(): String => "without pooling a segment update lasts the step it was queued"

  fun apply(h: TestHelper) ? =>
    // the reference: there is no point having a longer expiration if we are not
    // doing pooling
    h.assert_eq[USize](1, TemporalPoolerConfig(4, 3)?.update_window)
    h.assert_eq[USize](5, TemporalPoolerConfig(4, 3, 12, 8, 15, true)?.update_window)

class iso _APoolerWithoutNodesIsRefused is UnitTest
  fun name(): String => "a pooler with no nodes is refused"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => TemporalPoolerConfig(0, 3)? })

class iso _APoolerWithoutCellsInANodeIsRefused is UnitTest
  fun name(): String => "a pooler whose nodes have no cells is refused"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => TemporalPoolerConfig(4, 0)? })

class iso _APamLengthOfZeroIsRefused is UnitTest
  fun name(): String => "a pam length of zero is refused"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => TemporalPoolerConfig(4, 3, 12, 8, 15, false, 0.11, 0.5, 0.1, 0.1, 1.0, 0.1, 5, 0)? })

class iso _FixedSizeNeedsBothLimits is UnitTest
  fun name(): String => "a bounded pooler needs both bounds"

  fun apply(h: TestHelper) =>
    // the fixed-size mode is the pair; one of them alone leaves the other kind
    // of memory growing without limit
    h.assert_error({() ? => TemporalPoolerConfig(
      4, 3, 12, 8, 15, false, 0.11, 0.5, 0.1, 0.1, 1.0, 0.0, 5, 1, 10, 5, 0, 32, 4, 0)? })
    h.assert_error({() ? => FixedSize.config(0.0, 0, 0)? })

class iso _FixedSizeRefusesAGlobalDecay is UnitTest
  fun name(): String => "a bounded pooler refuses a global decay"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => FixedSize.config(0.1)? })

class iso _FixedSizeRefusesAnAgeLimit is UnitTest
  fun name(): String => "a bounded pooler refuses an age limit"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => FixedSize.config(0.0, 1000)? })

class iso _FixedSizeRefusesFewerSynapsesThanASegmentWants is UnitTest
  fun name(): String => "a bounded segment has to be able to hold what a segment wants"

  fun apply(h: TestHelper) =>
    // fifteen synapses wanted, ten allowed
    h.assert_error({() ? => FixedSize.config(0.0, 0, 10)? })

class iso _FixedSizeWithConsistentLimitsIsAccepted is UnitTest
  fun name(): String => "bounds that agree with each other are accepted"

  fun apply(h: TestHelper) ? =>
    let bounded = FixedSize.config()?
    h.assert_true(bounded.fixed_size())
    h.assert_eq[USize](4, bounded.max_segments_per_cell)
    h.assert_eq[USize](20, bounded.max_synapses_per_segment)
