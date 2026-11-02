use "collections"
use ".."

class val GraphEdge
  """
  One edge of a graph: where it leaves and where it arrives.

  Direction is part of the edge, not a decoration on it. `a -> b` and `b -> a`
  are two different edges and encode differently, because the encoder writes the
  arriving node further along the vector than the leaving one.
  """
  let from: String
  let to: String

  new val create(from': String, to': String) =>
    from = from'
    to = to'

class GraphEncoder
  """
  A graph - nodes and the edges between them - as one representation.

  Nothing in the references does this, so this is a design rather than a port,
  and the design is three decisions:

  * a node is a category, encoded by the open-set category encoder, so a node met
    again anywhere in the graph gets the bits it had before and a node met for the
    first time costs nothing but its own bits;
  * an edge is the concatenation of its two nodes, the arriving one shifted by
    the width, which is what makes direction part of the edge rather than a flag
    beside it;
  * a graph is the union of its edges' positions, optionally subsampled, so the
    order the edges are listed in cannot matter and two graphs that share edges
    share positions.

  The third decision is the one worth arguing about. A union loses multiplicity -
  two edges that encode to the same positions are one - and it lets one busy
  region of the graph dominate the representation. The alternative, a bag of edge
  representations kept apart, is a set of representations rather than one, which
  is what a pooler cannot consume.
  """
  let width: USize
  let bits: USize
  let most: USize
  let _nodes: SDRCategoryEncoder

  new create(
    width': USize,
    bits': USize = 0,
    most': USize = 0,
    seed: U64 = 42)
    ?
  =>
    """
    A width of `width'` positions for a node, `bits'` of them on per node, and at
    most `most'` positions for a whole graph - zero for no cap, which is what a
    small graph can afford and a large one cannot.
    """
    _nodes = SDRCategoryEncoder(width', bits', seed)?
    width = width'
    bits = _nodes.bits_on()
    most = most'

  fun nodes(): USize =>
    """
    How many nodes have been met.
    """
    _nodes.labels()

  fun knows(node: String): Bool =>
    """
    Whether this node has been met before.
    """
    _nodes.knows(node)

  fun ref encode(edges: ReadSeq[GraphEdge]): Array[USize] val =>
    """
    The representation of a graph given its edges.

    Nodes are met as the edges are read, so a node that appears only in the edge
    that mentions it still gets its own bits - and keeps them for every graph
    this encoder is asked about afterwards.
    """
    let merged = Set[USize]

    for edge in edges.values() do
      let leaving = _nodes.encode(edge.from)
      let arriving = _nodes.encode(edge.to)

      for position in SDRMerger.concat(leaving, arriving, width).values() do
        merged.set(position)
      end
    end

    let collected: Array[USize] iso = recover iso Array[USize] end
    for position in merged.values() do
      collected.push(position)
    end

    let cap = if most == 0 then collected.size() else most end
    SDRMerger.subsample(consume collected, cap)
