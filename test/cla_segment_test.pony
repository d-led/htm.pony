use "pony_test"
use "../htm"

// The Go reference: temporalPooler.getSegmentActivityLevel and isSegmentActive,
// and segment.go's Segment.dutyCycle.

class ClaSegmentTest is TestList
  fun name(): String => "CLA segment"

  fun tag tests(test: PonyTest) =>
    test(_ActivityIsTheSynapsesOntoActiveCells)
    test(_AWeakMatchIsNotAPrediction)
    test(_EnoughConnectedSynapsesPredict)
    test(_ASegmentWithTooFewSynapsesNeverPredicts)
    test(_ACellIsReachedOnlyOnce)
    test(_WithLittleHistoryTheRecordIsTheEstimate)
    test(_TheEstimateDecaysWhileNothingGoodHappens)
    test(_AGoodStepRaisesTheEstimate)
    test(_AskingTwiceAtTheSameStepAnswersTheSame)

primitive ClaStates
  """
  A state to read a segment against: the cells that are on, in a population of a
  given size.
  """
  fun of(active: ReadSeq[USize], cells: USize): Array[Bool] =>
    let state = Array[Bool].init(false, cells)
    for cell in active.values() do
      try state(cell)? = true end
    end
    state

  fun near(h: TestHelper, expect: F64, actual: F64) =>
    h.assert_true((expect - actual).abs() < 0.00000001,
      "expected " + expect.string() + ", got " + actual.string())

class iso _ActivityIsTheSynapsesOntoActiveCells is UnitTest
  fun name(): String => "activity is how many synapses reach a cell that is active"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(1)
    segment.add_synapse(0, 0.1)
    segment.add_synapse(1, 0.1)
    segment.add_synapse(2, 0.1)

    // two of the three cells it reaches are on, and it does not care how weakly
    h.assert_eq[USize](2, segment.activity(ClaStates.of([1; 2], 4)))

class iso _AWeakMatchIsNotAPrediction is UnitTest
  fun name(): String => "a segment whose synapses are all too weak does not predict"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(1)
    segment.add_synapse(0, 0.1)
    segment.add_synapse(1, 0.1)
    segment.add_synapse(2, 0.1)
    let state = ClaStates.of([0; 1; 2], 4)

    h.assert_eq[USize](3, segment.activity(state))
    h.assert_false(segment.active(state, 3, 0.5))

class iso _EnoughConnectedSynapsesPredict is UnitTest
  fun name(): String => "enough connected synapses onto active cells make a prediction"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(1)
    var cell: USize = 0
    while cell < 4 do
      segment.add_synapse(cell, 0.6)
      cell = cell + 1
    end

    // three of the four are on, and three connected ones is what it takes
    h.assert_true(segment.active(ClaStates.of([0; 1; 2], 4), 3, 0.5))
    h.assert_false(segment.active(ClaStates.of([0; 1], 4), 3, 0.5))

class iso _ASegmentWithTooFewSynapsesNeverPredicts is UnitTest
  fun name(): String => "a segment with fewer synapses than the threshold never predicts"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(1)
    segment.add_synapse(0, 0.6)
    segment.add_synapse(1, 0.6)

    h.assert_false(segment.active(ClaStates.of([0; 1], 4), 3, 0.5))

class iso _ACellIsReachedOnlyOnce is UnitTest
  fun name(): String => "a cell is reached by one synapse, however often it is added"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(1)
    segment.add_synapse(7, 0.1)
    segment.add_synapse(7, 0.6)

    h.assert_eq[USize](1, segment.synapses.size())
    h.assert_eq[USize](1, segment.activity(ClaStates.of([7], 8)))

class iso _WithLittleHistoryTheRecordIsTheEstimate is UnitTest
  fun name(): String => "with little history the estimate is the record itself"

  fun apply(h: TestHelper) =>
    // a segment is born with one activation behind it, and until there is more
    // history than a hundred steps its duty cycle is that over the steps
    let late = ClaSegment(10)
    let early = ClaSegment(4)
    h.assert_eq[F64](0.1, late.duty_cycle(10, false))
    h.assert_eq[F64](0.25, early.duty_cycle(4, false))

class iso _TheEstimateDecaysWhileNothingGoodHappens is UnitTest
  fun name(): String => "the estimate decays while nothing good happens"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(0)
    ClaStates.near(h, 1.0, segment.duty_cycle(0, false))
    ClaStates.near(h, 0.01, segment.duty_cycle(100, false))
    // a hundred quiet steps past the first tier, each taking 0.0032 of a step
    ClaStates.near(h, 0.007257765, segment.duty_cycle(200, false))

class iso _AGoodStepRaisesTheEstimate is UnitTest
  fun name(): String => "a step that was predicted well raises the estimate by one step"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(0)
    ClaStates.near(h, 0.01, segment.duty_cycle(100, false))
    // 0.01 held through one quiet step, and then one step of good news
    ClaStates.near(h, 0.013168, segment.duty_cycle(101, true))

class iso _AskingTwiceAtTheSameStepAnswersTheSame is UnitTest
  fun name(): String => "asking twice about the same step answers the same"

  fun apply(h: TestHelper) =>
    let segment = ClaSegment(0)
    let first = segment.duty_cycle(300, false)
    h.assert_eq[F64](first, segment.duty_cycle(300, false))
