# Spatial pooler

The spatial pooler turns an input into a sparse representation: the columns that
recognise it. It wires columns to the input, counts what they recognise, holds a
competition, and - when told to learn - moves its permanences in reaction to who
won.

Four stages:

1. **Wire** each column to a stretch of the input, and give each connection a
   permanence.
2. **Overlap**: count the active inputs a column's connected synapses see.
3. **Inhibit**: keep the columns that stand out and silence the rest.
4. **Answer**: the survivors are the representation.

A round that learns adds a fifth: the winners move their permanences, the
starving columns are raised and boosted, and activity is remembered. See
[learning](#learning).

## Configuration

`SpatialPoolerConfig` is a value, so it can be given to an actor. Every field
except the two shapes has a default.

| Field | Default | Meaning |
| --- | --- | --- |
| `column_dimensions` | — | the shape of the column grid, e.g. `[8; 8]` |
| `input_dimensions` | — | the shape of the input, e.g. `[64]` |
| `global_inhibition` | `false` | `true` competes across all columns, `false` among neighbours |
| `num_active_columns_per_inh_area` | `10.0` | how many columns may stay active per inhibition area |
| `local_area_density` | `-1.0` | a density stated outright; anything `<= 0` means "derive it" |
| `potential_radius` | `16` | how far from its centre a column may reach in the input |
| `potential_pct` | `0.5` | the share of the reachable inputs a column actually connects to |
| `connection_threshold` | `0.1` | the permanence at which a synapse counts as connected |
| `permanence_increment` | `0.1` | how far a permanence grows in a round where its input is on, and how far the seed spreads above the threshold |
| `inhibition_radius` | `1` | how far inhibition looks, in columns |
| `permanence_decrement` | `0.01` | how far a permanence shrinks in a round where its input is off |
| `stimulus_threshold` | `0` | the connections a column needs before its claim counts at all |
| `duty_cycle_period` | `1000` | the rounds the moving averages of activity are kept over |
| `max_boost` | `10.0` | the most a column that never wins is multiplied by |
| `min_overlap_duty_cycle` | `0.001` | the share of the busiest overlap rate below which a column is raised |
| `min_active_duty_cycle` | `0.001` | the share of the busiest win rate below which a column is boosted |

```pony
let config = SpatialPoolerConfig([8; 8], [64], false, 2.0)
```

That is 64 columns over a 64-bit input, competing locally with two active
columns per inhibition area.

## Wiring

A column is not given the whole input. It gets a receptive field: the inputs
around its own position, spread evenly across the input and widened by
`potential_radius`. It then connects to a random share of that field.

The centre of a column's field is its position scaled onto the input:

```text
centre = truncate((inputs - 1) * column / (columns - 1))
```

With 64 columns over 64 inputs, column 9 lands on centre 9 and column 63 lands
on centre 63. The value is computed in floating point and truncated towards
zero, which for a non-negative result matches rounding down.

The field is `centre - potential_radius` to `centre + potential_radius`, clipped
to the input. Those two rules give the numbers in the example:

| Column | Centre | Field | Inputs in field | Synapses |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0..16 | 17 | 9 |
| 9 | 9 | 0..25 | 26 | 13 |
| 31 | 31 | 15..47 | 33 | 17 |
| 63 | 63 | 47..63 | 17 | 9 |

The synapse count is `potential_pct` of the field, rounded: half of 33 is 16.5,
which rounds to 17; half of 17 is 8.5, which rounds to 9. Columns at the ends of
the input reach less far, because their fields are clipped, so they connect to
fewer inputs than columns in the middle.

The connected inputs are chosen by shuffling the field and taking the first
*count*. Shuffling rather than sampling means a column never connects to the
same input twice, which the permanence initialisation would happily allow
otherwise.

### Initial permanence

Each connection starts on one of two sides of the connection threshold:

- half start just above it, at `threshold + random * increment / 4`, so a little
  learning can push them back below and break the connection;
- half start below it, at `threshold * random`, so they are connected only if
  learning strengthens them.

So roughly half of a column's synapses are connected before any learning
happens. The two-sided start is what gives learning something to move in both
directions; the alternative, starting everything connected, leaves the column
with no room to unlearn.

Connection is derived from the permanence by comparing it with the threshold. It
is not stored, so learning will update one number per synapse instead of keeping
a separate connection flag in step with it.

## Overlap

A column's overlap is how many of its connected synapses see an active input
bit:

```pony
let overlap = column.overlap(input, config.connection_threshold)?
```

Two functions compute this, and the difference matters:

| | Behaviour on a synapse outside the input |
| --- | --- |
| `Column.overlap` | raises |
| `Synapses.overlap` | skips the synapse |

`Column.overlap` belongs to a caller that owns the input width. A column that
reaches past it is a wiring error, and raising reports it at the call that
caused it.

`Synapses.overlap` is total because an actor constructor cannot fail. A shard is
built with synapses that have already been checked, so the skip never fires in
practice; it exists so that the function has no error case to leak into an actor.

## Inhibition

Overlap alone does not choose the representation. Many columns can have the same
overlap, and a column that matches nothing has no claim at all.

Two rules hold in both modes:

- a column with overlap `0` cannot win;
- the number of winners comes from a density, so the same setting keeps its
  meaning as the inhibition radius grows.

### Global inhibition

`Inhibition.winners(overlaps, count)` keeps the `count` strongest columns and
returns them in ascending column order. Ties go to the earlier column. Returning
column order rather than discovery order means the result does not depend on
where the strongest column happened to be found.

### Local inhibition

`Inhibition.local(overlaps, grid, radius, density)` compares each column only
with its neighbours. Two distant regions of the grid can therefore each be
represented by their own strongest column, which global inhibition would forbid.

A column wins when fewer than the area's allowance of its neighbours outrank it.
The allowance counts the column itself:

```text
allowance = truncate(density * (neighbours + 1) + 0.5)
```

The `+ 0.5` makes the truncation round to the nearest whole number instead of
down.

With a density of 0.2222 and radius 1, a column in the middle of an `[8; 8]`
grid has 8 neighbours, so the allowance is 2: a column wins if at most one
neighbour outranks it. A column in a corner has 3 neighbours, so the allowance
is 1 and nothing but a tie may beat it.

Counting the column itself is what makes a corner column able to win at all.
Without it, a density that rounds to zero would silence every column.

### Density

`config.density(radius)` returns the fraction of an area that may stay active.
`local_area_density` wins if it is positive. Otherwise the pooler converts
`num_active_columns_per_inh_area` into a fraction of one area, and caps it at one
half:

```pony
let config = SpatialPoolerConfig([8; 8], [64], false, 2.0)
config.density(1)  // 0.222222
```

The area of radius 1 on an `[8; 8]` grid is 9 cells, so 2 columns is 2/9, about
0.222. The cap stops a small area from asking for more winners than it holds
cells.

## A worked example

The [in-process example](examples.md#the-spatial-pooler-in-one-process) builds a
pooler from `[8; 8]` columns over a 64-bit input, seed 42, with six input bits
set:

```
active input bits: 3, 5, 8, 13, 21, 44
representation:    3, 5, 7, 8, 13, 17, 19, 28, 42, 45, 55, 56
```

Six active inputs out of 64 become twelve active columns out of 64. The columns
are not the input positions: column 3 is not active because input 3 is, it is
active because the column wired around input 3 happens to connect to several of
the active bits.

## Determinism

Wiring takes a seed. The same seed and the same input give the same
representation, which is what makes the examples checkable and the tests
comparable.

```pony
let pooler = SpatialPooler(config, 42)?
let again = SpatialPooler(config, 42)?
pooler.compute(input)? == again.compute(input)?   // the same representation
```

Different seeds wire different columns to different inputs. Neither wiring is
better; they are different populations that recognise different things.

## On actors

The same computation also runs as messages between actors, with the columns
grouped into shards and a coordinator collecting their votes. That path computes
the same representation from the same seed and learns from the same rounds; its
example runs sixty learning rounds on both and compares the answer to every one.
[Actors](actors.md) describes it.

Learning is decided in one place on both paths. Inhibition can name a winner only
after every overlap is known, so the coordinator holds the round until the tally
comes back and then sends each shard the columns that are to move. A shard
applies the arithmetic to the columns it owns and decides nothing.

## Learning

A round that learns moves the pooler forward before the next round:

```pony
pooler.compute(input, true)?     // learn
pooler.compute(input, false)?    // look, change nothing
```

Four things happen, in the order the Go reference does them.

**The winners move.** Each winning column strengthens the synapses whose input
was on, by `permanence_increment`, and weakens every other one by
`permanence_decrement`. The two are deliberately lopsided - a tenth against a
hundredth by default - so a column learns quickly and forgets slowly. A
permanence is a belief between nought and one and never leaves that range. Once
weakened below half a learning step, a connection is let go of: its permanence
becomes zero, and it stops contributing to the overlap without the column
forgetting where it used to look.

**What stays silent is raised.** A column whose overlap is far below what its
neighbourhood manages has its whole receptive field raised by a tenth of the
connection threshold. Without that, a column that never wins can only weaken,
and a column that never wins can never learn.

**Activity is remembered.** Two moving averages per column, over
`duty_cycle_period` rounds: how often it overlapped at all, and how often it won.

**Columns that keep losing are boosted.** A column whose activity is below a
fraction (`min_active_duty_cycle`) of the busiest column is boosted up to
`max_boost`, and the boost multiplies its overlap before inhibition. One means
nothing is being done; ten means the column is helped strongly. This is what
keeps a population from collapsing onto the few columns that happened to win
first.

```pony
pooler.boost_factor(column)?    // 1.0: being heard. above 1.0: being helped
```

Two consequences are worth knowing before trusting this.

A boost is a multiplier on an overlap count, so a column with a weak claim times
ten can beat a column with a strong claim. Feed the same input for long enough
and the representation will start to move: the columns that never won are
helped until they do. That is what the reference does, and it is why the pooler
wants a stream that varies rather than one repeated pattern.

Whether a trained pooler does better with a *damaged* version of a pattern
depends on the damage. A pattern that loses bits is reached far better by a
pooler that learned it; a pattern that gains bits it never had is a wash.
[What learning is worth](examples.md#what-learning-is-worth) measures both kinds
and prints the tables.

What learning demonstrably does - and what the tests check - is move permanences
towards what a column won with, raise the columns that are starving, and remember
who wins.

### What is not ported

Two pieces of the reference are deliberately absent.

`updateInhibitionRadius` re-derives the inhibition radius every fiftieth round
from the average span each column connects over. Here the radius is what the
configuration says, because it is also the radius `local` inhibition searches a
real neighbourhood with; deriving it would silently change which columns compete
with which. The radius therefore stays put.

`stripNeverLearned` removes columns that have never won from an inference
answer. It is not ported because it makes a freshly built pooler answer
*nothing* - nothing has been learned yet - which would break the
[inference-only path](examples.md#the-spatial-pooler-in-one-process) that this
port ships. What it protects against is a column that never won winning by
accident; the boost mechanism is the gentler half of the same idea.

## What is not here

A temporal memory can be put on top of the pooler, and reading this page's
permanences is how you would see what it learned. What is missing is a graph
encoder, and any measurement of whether a trained pooler is better than a wired
one at a task: that benchmark does not exist yet.
