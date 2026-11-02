use "pony_test"
use "../htm"
use "../htm/encoders"

class GraphEncoderTest is TestList
  fun name(): String => "Graph encoder"

  fun tag tests(test: PonyTest) =>
    test(_AnEdgeIsTwoNodesAndADirection)
    test(_TheOrderOfTheEdgesDoesNotMatter)
    test(_AReversedEdgeIsAnotherEdge)
    test(_AGraphThatSharesAnEdgeSharesItsBits)
    test(_ALargeGraphIsCapped)
    test(_ANodeKeepsItsBitsFromOneGraphToTheNext)

primitive Edges
  fun of(from: String, to: String): GraphEdge => GraphEdge(from, to)

  fun below(indices: ReadSeq[USize], limit: USize): Array[USize] val =>
    let kept: Array[USize] iso = recover iso Array[USize] end
    for index in indices.values() do
      if index < limit then kept.push(index) end
    end
    consume kept

  fun shared(one: ReadSeq[USize], other: ReadSeq[USize]): USize =>
    var count: USize = 0
    for index in one.values() do
      for other_index in other.values() do
        if index == other_index then count = count + 1 end
      end
    end
    count

class iso _AnEdgeIsTwoNodesAndADirection is UnitTest
  fun name(): String => "an edge is its two nodes, the second one further along"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4)?

    // the leaving node's bits are under 64, the arriving node's from 64 up, so
    // the two cannot collide and an edge is exactly twice a node
    let graph = encoder.encode(recover val [Edges.of("a", "b")] end)

    h.assert_eq[USize](8, graph.size())
    h.assert_eq[USize](2, encoder.nodes())

class iso _TheOrderOfTheEdgesDoesNotMatter is UnitTest
  fun name(): String => "the order the edges are listed in does not matter"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4)?

    let forwards = encoder.encode(
      recover val [Edges.of("a", "b"); Edges.of("b", "c")] end)
    let backwards = encoder.encode(
      recover val [Edges.of("b", "c"); Edges.of("a", "b")] end)

    h.assert_array_eq[USize](forwards, backwards)

class iso _AReversedEdgeIsAnotherEdge is UnitTest
  fun name(): String => "a reversed edge is another edge"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4)?

    let one_way = encoder.encode(recover val [Edges.of("a", "b")] end)
    let the_other = encoder.encode(recover val [Edges.of("b", "a")] end)

    h.assert_eq[USize](one_way.size(), the_other.size())
    h.assert_eq[USize](0, Edges.shared(one_way, the_other))

class iso _AGraphThatSharesAnEdgeSharesItsBits is UnitTest
  fun name(): String => "two graphs that share an edge share that edge's bits"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4)?

    let first = encoder.encode(
      recover val [Edges.of("a", "b"); Edges.of("b", "c")] end)
    let second = encoder.encode(
      recover val [Edges.of("a", "b"); Edges.of("c", "d")] end)
    let unrelated = encoder.encode(
      recover val [Edges.of("x", "y"); Edges.of("z", "w")] end)

    // the shared edge is eight positions of its own; two nodes may also share a
    // bit or two by chance, which is the price of random categories
    h.assert_true(
      Edges.shared(first, second) >= 8,
      "a shared edge is at least its own eight positions")
    h.assert_true(
      Edges.shared(first, second) > Edges.shared(first, unrelated),
      "sharing an edge shares more than sharing nothing")

class iso _ALargeGraphIsCapped is UnitTest
  fun name(): String => "a graph bigger than the cap is cut down to it"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4, 10)?

    let edges: Array[GraphEdge] val = recover val
      let many = Array[GraphEdge]
      var index: USize = 0
      while index < 20 do
        many.push(Edges.of("n" + index.string(), "m" + index.string()))
        index = index + 1
      end
      many
    end

    h.assert_eq[USize](10, encoder.encode(edges).size())

class iso _ANodeKeepsItsBitsFromOneGraphToTheNext is UnitTest
  fun name(): String => "a node met again is the same node"

  fun apply(h: TestHelper) ? =>
    let encoder = GraphEncoder(64, 4)?

    let first = encoder.encode(recover val [Edges.of("a", "b")] end)
    let second = encoder.encode(recover val [Edges.of("a", "c")] end)

    // three nodes met, not four, and "a"'s bits are where they were
    h.assert_eq[USize](3, encoder.nodes())
    h.assert_array_eq[USize](Edges.below(first, 64), Edges.below(second, 64))
