# Actors

The spatial pooler also runs as messages. The computation does not change: the
same wiring, the same overlap, the same inhibition. What changes is where it
runs and how the answer travels.

The actor path exists so that columns can be spread across cores, and so that a
slow or absent column cannot hold up a round.

## The shape of the path

```text
Asker        --represent(active, learn, asker)-->  Pooler
Pooler       --observe(active, ballot)-->          ColumnShard, once per shard
ColumnShard  --cast(votes)-->                      BallotBox
BallotBox    --tallied(votes)-->                   Pooler
Pooler       --learn(active, winners, starving)--> ColumnShard, once per shard
Pooler       --represented(winners)-->             Asker
```

No step returns a value. The asker hands over a `Representation` and the answer
arrives at `represented` when the round closes. That is what lets a round be in
flight while the caller does something else.

A round that learns has one more step, and it comes last because only the votes
say who won. The input the round learned from has to be kept until then, which
is why the pooler holds the round rather than forgetting it once the shards have
been asked.

## Four interfaces and nothing else

The actors do not name each other's types:

```pony
interface Ballot
  be vote(vote': Vote)
  be cast(votes: Array[Vote] iso)

interface Tally
  be tallied(votes: Array[Vote] iso)

interface Shard
  be observe(active: Array[Bool] val, ballot: Ballot tag)
  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val)

interface Representation
  be represented(active: Array[USize] iso)
```

A column pushes into a `Ballot` and never learns what collects the votes. The
ballot box pushes into a `Tally` and never learns what asked. The pooler asks a
`Shard` and never learns which band of columns answers. An asker implements
`Representation` and is handed the answer.

The practical effect is that a shard can be tested against any sink, and a sink
against any source. `test/column_shard_test.pony` and `test/ballot_box_test.pony`
do exactly that. The same seam puts any band of columns behind the pooler,
including one that answers nothing.

## The vote

```pony
class val Vote
  let column: USize
  let overlap: F64
```

A vote is one column's claim: which column it is, and how strongly it matches.
It is a value, so it can be sent between actors and copied into a tally.

## The ballot box

`BallotBox` collects the votes on one question. The round is over as soon as any
of these happens, whichever comes first:

- every expected vote has arrived;
- a predefined quorum has arrived, so a few slow columns cannot hold up the
  answer;
- a deadline expires, when one was set.

```pony
let box = BallotBox(collector, columns, quorum = columns / 2, deadline_ms = 50)
```

Two guards keep the constructor from building a round that cannot close:

```pony
_quorum =
  if (quorum == 0) or (quorum > expected) then expected else quorum end
```

A quorum of zero would decide an empty question immediately, and a quorum larger
than the number of columns would wait forever. Both become "all of them".

A vote that arrives after the round is decided is dropped. Without the guard, a
straggler would deliver a second `tallied` to the same collector, and the
collector would answer the same question twice.

`cast` is the bulk form: a whole shard's votes in one message. Each vote counts
towards the quorum, so the caller's numbers stay in votes however the columns
are grouped.

The deadline is a `TimerNotify` that returns `false` from `apply`, so it fires
once. A repeating timer would decide a round that had already been decided.

## Shards

`ColumnShard` is a band of columns sharing one actor:

```pony
actor ColumnShard is Shard
  let _columns: Array[Column] ref
  let _indices: Array[USize] val
  let _positions: Map[USize, USize] ref
  let _config: SpatialPoolerConfig val

  be observe(active: Array[Bool] val, ballot: Ballot tag) =>
    /* one vote per column, in one cast */

  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val) =>
    /* adapt the winners, raise the starving ones */
```

One actor per column would cost a message in and a message out for every
column. A shard costs that once for the whole band and reports its votes in a
single message. The ballot box still counts votes, not messages, so grouping
columns does not change when a round closes. A band of one column is the
single-column case and needs nothing else.

A shard holds the settings that decide what a column claims and how far it
moves, so `learn` carries the input and the names of the columns the pooler
chose, and nothing else. Those names are indices in the population, not
positions in the band: the pooler decides who learns and knows only the
population, so each shard looks up the columns that are its own and ignores the
rest. That lookup is why the shard keeps a `Map` beside its columns.

The wiring arrives as values - a `ColumnWiring` is an index and a frozen array
of synapses - and the shard does not validate it at construction: an actor
constructor cannot fail, so there is no place to report a connection that reaches
past the end of the input. The pooler settles the input width first and hands
over synapses that fit. `Synapses.overlap` skips anything that does not, which is
the backstop rather than the rule.

## The coordinator

`Pooler` is the actor that asks and answers.

```pony
let pooler = Pooler(shards, Grid([8; 8])?, config)
pooler.represent(active, learn, asker)
```

It runs one round at a time. A second request waits in a queue rather than
overwriting a tally still in flight:

```pony
be represent(active: Array[Bool] val, learn: Bool, asker: Representation tag) =>
  _queue.push(Round(active, learn, asker))
  _pump()
```

When the tally arrives the pooler inhibits the votes. On a learning round it
raises the claims of the columns that keep losing before inhibiting, remembers
who claimed what and who won, and sends each shard the two lists of columns that
are to move. Then it pushes the winners to the asker and takes the next request.

The shards are told before the asker is answered, so a round's `learn` leaves
before the next round's `observe`. Messages from one actor to another arrive in
the order they were sent, so a shard cannot be shown the next input before it has
learned from the last one - and nothing waits for a shard to acknowledge the
`learn`.

The ballots it creates expect one vote per column and set the quorum to the same
number. That means a round closes when every shard has answered, and without a
deadline that is the only way it closes:

```pony
let pooler = Pooler(shards, grid, config, 50)   // fifty milliseconds
```

With a deadline the round also closes on the votes that arrived in time. Columns
that stayed silent claim nothing, and the round learns from the representation
those votes produce, so a slow shard costs accuracy rather than the answer. A
shard that answers after the deadline is dropped, the same guard the ballot box
applies to any straggler.

## Ordering and ties

Votes are stored in the order they arrive, which is not the column order. The
inhibition stage rebuilds the overlaps into a column-indexed array before
deciding, so arrival order cannot change the representation.

`tallied` reports the winners to `represented` in whatever order inhibition
produced them, which is ascending column order in both modes.

## The temporal memory, on actors

The sequence side runs as actors too, and its shape is different enough to be
worth stating. `TemporalMemory` holds one `TemporalColumn` per
column, and a column needs the previous step, its own segments and whether
it is active - nothing that belongs to another column. That is what makes the
split honest rather than a copy: the shards own the state.

```pony
let region = TemporalRegion(
  params, TemporalShards.build(params, 16))   // bands of sixteen columns
region.compute(active_columns, true, an_observer)
```

A step is **two passes**, not one:

1. `activate` - each shard decides the cells its columns activate, learns from
the decision, and reports which cells fired and which of its columns burst.
2. `predict` - now that every column has answered, the region has the new
state; each shard says which of its cells that state makes it expect.

The second pass cannot be folded into the first. A prediction is about a state
that includes what every other column did, and no shard knows that on its own.
The region answers an asker only when both passes are back, so a caller never
sees half a step.

Two behaviours differ from the in-process memory, both because an actor cannot
refuse a message. A column the memory was not built for is ignored rather than
refused, and a region with no shards answers every step with nothing active. The
example prints both paths side by side and compares them step by step; they
agree, which is the only reason to believe the split.

## What is missing

- No retry when a shard does not answer, and no way to tell a slow shard from a
  dead one. A deadline closes the round on the votes that arrived, so a late
  shard costs accuracy rather than the answer, but the pooler cannot report that
  a shard is missing.
- No way to add or remove a shard while the pooler is running.
- No supervision: an actor that crashes is gone, and the pooler waits.
- One pooler is one coordinator. Two poolers over the same shards would each
  start their own rounds.
- The temporal region inherits the same gaps: no deadline, no retry, no
  supervision, and one region per set of shards.
