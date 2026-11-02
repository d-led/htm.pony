use "pony_test"
use "../htm"

// The Go reference: temporalPooler.getBestMatchingSegment, and the cells it is
// asked about.

class ClaCellTest is TestList
  fun name(): String => "CLA cell and node"

  fun tag tests(test: PonyTest) =>
    test(_ANewSegmentIsOnTheCellThatMadeIt)
    test(_TheBestSegmentIsTheClosestToTheState)
    test(_NothingCloseEnoughMeansNoBestSegment)
    test(_ATieGoesToTheLaterSegment)
    test(_ANodeOwnsItsCells)

primitive ClaCells
  """
  A cell whose segments match a state by as many synapses as it is told.

  Every segment reaches `synapses` cells; the ones which should match reach
  cells the state leaves on, and the rest reach cells far away from it.
  """
  fun with_segments(matched: ReadSeq[USize], synapses: USize): ClaCell =>
    let cell = ClaCell(0, 0)

    for wanted in matched.values() do
      let segment = cell.new_segment(1)
      var index: USize = 0
      while index < synapses do
        if index < wanted then
          segment.add_synapse(index, 0.6)
        else
          segment.add_synapse(100 + index, 0.6)
        end
        index = index + 1
      end
    end

    cell

class iso _ANewSegmentIsOnTheCellThatMadeIt is UnitTest
  fun name(): String => "a new segment belongs to the cell that made it"

  fun apply(h: TestHelper) =>
    let cell = ClaCell(1, 2)
    let segment = cell.new_segment(3)

    h.assert_eq[USize](1, cell.segments.size())
    // and it knows how old it is, which is how a memory is aged out
    h.assert_eq[U64](2, segment.age(5))

class iso _TheBestSegmentIsTheClosestToTheState is UnitTest
  fun name(): String => "the best segment is the one closest to the state"

  fun apply(h: TestHelper) ? =>
    let cell = ClaCells.with_segments([1; 4; 2], 5)
    let state = ClaStates.of([0; 1; 2; 3], 8)

    match cell.best_segment(state, 2)
    | let best: ClaSegment =>
      h.assert_true(best is cell.segments(1)?, "the segment that matched four")
    | None => h.fail("nothing matched, but one segment matched four synapses")
    end

class iso _NothingCloseEnoughMeansNoBestSegment is UnitTest
  fun name(): String => "nothing close enough means there is no segment to learn on"

  fun apply(h: TestHelper) =>
    let cell = ClaCells.with_segments([1; 2], 5)
    let state = ClaStates.of([0; 1; 2; 3], 8)

    match cell.best_segment(state, 3)
    | let best: ClaSegment => h.fail("a segment matched less than the threshold")
    | None => None
    end

class iso _ATieGoesToTheLaterSegment is UnitTest
  fun name(): String => "a tie goes to the later segment"

  fun apply(h: TestHelper) ? =>
    // the reference replaces the best it has whenever a segment is not worse,
    // so the last of the equals answers
    let cell = ClaCells.with_segments([2; 2], 5)
    let state = ClaStates.of([0; 1; 2; 3], 8)

    match cell.best_segment(state, 2)
    | let best: ClaSegment =>
      h.assert_true(best is cell.segments(1)?, "the second of the two")
    | None => h.fail("neither segment was found")
    end

class iso _ANodeOwnsItsCells is UnitTest
  fun name(): String => "a node owns the cells that carry its states"

  fun apply(h: TestHelper) ? =>
    let node = ClaNode(2, 4)

    h.assert_eq[USize](2, node.index)
    h.assert_eq[USize](4, node.cells().size())

    let third = node.cells()(3)?
    h.assert_eq[USize](3, third.offset)
    h.assert_eq[USize](2, third.node)
