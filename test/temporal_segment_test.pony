use "pony_test"
use "../htm"

primitive TemporalSegmentTest
  fun tag tests(test: PonyTest) =>
    test(_AConnectedSynapseLearnsFromActivity)
    test(_ActivityAloneDoesNotRebuildACutConnection)

class iso _AConnectedSynapseLearnsFromActivity is UnitTest
  fun name(): String =>
    "a synapse already connected is strengthened when its cell was active"

  fun apply(h: TestHelper) ? =>
    let segment = TemporalSegment(0)
    segment.connect_to([0], 0.5, 1)

    // the cell this segment reaches fired, and the connection already claims it
    segment.strengthen([true], 0.5, 0.1, 0.01)

    h.assert_eq[F64](0.6, segment.synapses(0)?.permanence)

class iso _ActivityAloneDoesNotRebuildACutConnection is UnitTest
  fun name(): String =>
    "a synapse cut below connection decays even while its cell keeps firing"

  fun apply(h: TestHelper) ? =>
    let segment = TemporalSegment(0)
    segment.connect_to([0], 0.4, 1)

    // the same activity, on a connection a punishment has taken below the line
    segment.strengthen([true], 0.5, 0.1, 0.01)

    h.assert_eq[F64](0.39, segment.synapses(0)?.permanence)
