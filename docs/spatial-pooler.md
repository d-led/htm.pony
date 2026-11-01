# Spatial pooler

The spatial pooler turns an input into a sparse representation: the columns that
recognise it. It does not learn yet. What it does is wire columns to the input,
count what they recognise, and hold a competition.

Four stages:

1. **Wire** each column to a stretch of the input, and give each connection a
   permanence.
2. **Overlap**: count the active inputs a column's connected synapses see.
3. **Inhibit**: keep the columns that stand out and silence the rest.
4. **Answer**: the survivors are the representation.

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
| `permanence_increment` | `0.1` | how far the initial permanences spread above the threshold |
| `inhibition_radius` | `1` | how far inhibition looks, in columns |

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

$$
\text{centre} = \left\lfloor (\text{inputs} - 1) \cdot \frac{\text{column}}{\text{columns} - 1} \right\rceil
$$

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

$$
\text{allowance} = \left\lfloor \text{density} \cdot (\text{neighbours} + 1) + 0.5 \right\rfloor
$$

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

The area of radius 1 on an `[8; 8]` grid is 9 cells, so 2 columns is
$2/9 \approx 0.222$. The cap stops a small area from asking for more winners
than it holds cells.

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
the same representation and its example checks it against the in-process one.
[Actors](actors.md) describes it.

## What is not here

Learning. The permanences never change after wiring, so a column recognises the
inputs it was born connected to and nothing else.

That means the parts of the Go implementation called `adaptSynapses`,
`updateDutyCycles`, `bumpUpWeakColumns`, `updateBoostFactors` and
`updateInhibitionRadius` have no counterpart here. Boosting in particular exists
to give unused columns a chance; without learning, an unused column has nothing
to catch up on.
