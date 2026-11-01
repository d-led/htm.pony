class val Synapse
  """
  A connection from a cortical column to one input bit.

  A synapse only takes part in the column's overlap once its permanence has
  been learned up to the connection threshold; below it the connection exists
  but is too weak to count.
  """
  let input: USize
  let permanence: F64

  new val create(input': USize, permanence': F64) =>
    input = input'
    permanence = permanence'

  fun connected(threshold: F64): Bool =>
    permanence >= threshold
