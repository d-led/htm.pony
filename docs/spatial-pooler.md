# Spatial pooler

The spatial pooler turns an input into a sparse representation: the columns that
recognise it.

## How a column is wired

Each column is given a receptive field: the stretch of input around its own
position, spread evenly across the input and widened by a potential radius.
It connects to a random share of that field, and each synapse carries a
permanence.

A synapse counts as connected once its permanence reaches the connection
threshold. Connection is derived from the permanence rather than stored, so
learning will update one number instead of keeping two structures in step.

## Overlap

A column's overlap is how many of its connected synapses see an active input
bit. A column whose overlap is zero cannot win: it matches nothing, so it has no
claim to represent anything.

## Inhibition

Overlap alone does not choose the representation. Inhibition is the competition
that turns claims into a representation.

Global inhibition keeps the strongest columns across the whole population.
Local inhibition compares each column only with its neighbours, so two distant
regions can each be represented by their own strongest column. In both cases the
number of winners comes from a density, capped at one half of the area, so one
setting keeps its meaning as the inhibition radius grows.

## Running it on messages

The pooler does not compute in one loop when it does not have to. `ColumnShard`
actors own bands of columns and push their overlaps as votes into a ballot box.
The ballot box closes the round at whichever comes first: every expected vote, a
predefined quorum, or a deadline. A `Pooler` actor then inhibits the tally and
pushes the representation to whoever asked.

No behaviour returns a value, and no actor names the type of the one it talks
to: columns depend on the shape of a vote sink, and the ballot box depends on
the shape of a receiver.
