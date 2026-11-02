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
  be cast(band: USize, votes: Array[Vote] iso)

interface Tally
  be tallied(votes: Array[Vote] iso, silent: Array[USize] val)

interface Shard
  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag)
  be learn(active: Array[Bool] val, winners: Array[USize] val, starving: Array[USize] val)

interface Representation
  be represented(active: Array[USize] iso, missing: USize)
```

A column pushes into a `Ballot` and never learns what collects the votes. The
ballot box pushes into a `Tally` and never learns what asked. The pooler asks a
`Shard` and never learns which band of columns answers. An asker implements
`Representation` and is handed the answer, together with the number of columns
the round never heard from - zero for a round every column answered.

The one thing that does cross those seams is a band's name. A shard is told
which band it is and sends that name back with its votes, so a collector can tell
who has reported without knowing what any of them are. That is what makes a
silent band something the pooler can act on rather than only count.

The practical effect is that a shard can be tested against any sink, and a sink
against any source. `test/column_shard_test.pony` and `test/ballot_box_test.pony`
do exactly that. The same seam puts any band of columns behind the pooler,
including one that answers nothing.

Nothing here is locked, and nothing needs to be. An actor changes its state only
while it is running one of its own behaviours, one at a time, and the only way in
is a message - which Pony delivers in the order it was sent between any pair of
actors. A round is synchronized by the messages it is made of, not by anything
shared: the pooler asks, the shards answer, and nothing else is happening inside
them meanwhile. That is also why what crosses an actor boundary is a value - a
`Round` carries `Array[Bool] val`, a report carries `Array[Vote] iso` - the
capabilities say what may still be touched by whom.

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

`cast` is the bulk form: a whole shard's votes in one message, naming the band
they came from. Each vote counts towards the quorum, so the caller's numbers stay
in votes however the columns are grouped.

Give the box the bands it should hear from and it also reports which of them
never reported:

```pony
let box = BallotBox(collector, expected_votes, quorum, deadline_ms, bands)
```

That roster is the whole of what makes a retry possible. Without one the box
only counts votes, which is all it can do when the votes are not grouped into
bands.

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

  be observe(band: USize, active: Array[Bool] val, ballot: Ballot tag) =>
    /* one vote per column, in one cast that names the band */

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
applies to any straggler. The answer carries the count of columns that never
answered, so an asker can tell a representation the whole population agreed on
from one that part of it was never asked about.

A round that closes with bands missing is then asked a second time - of those
bands only, for one more deadline, on a ballot that expects only the votes still
owed. The bands that answered are not asked again, so a shard that was merely
busy costs one extra deadline and the round comes back complete. A shard that is
still busy after both deadlines is counted in `missing`. It is one retry and not
a policy: a round that waits longer than two deadlines is a round the caller
asked to bound.

There is no such thing here as a shard that is *gone*. A Pony actor stays alive
while anything can reach it - the pooler holds every one of them - and it runs
the behaviours it is given, in the order it is given them. Nothing in this
library spans processes, so a shard that does not answer within a deadline is
busy: inside a long behaviour, an FFI call, or a loop that does not end. The
compiler rules out the other silent failure, too: a behaviour must handle any
potential error, so a shard cannot abandon its report halfway through. Silence
here means time, not a missing answer. The deadline bounds how long a round waits
for it, and the retry gives it one more chance to be quick. Were this ever to run
across machines, that would stop being true and the retry would stop being enough.

Because the answer is held until the retry is over, the next request waits for
both deadlines. The alternative - answering at the first deadline and folding the
late votes in afterwards - would mean deciding, learning and *then* changing the
representation the round already acted on.

The bands can be replaced while the pooler is running:

```pony
pooler.reconfigure(new_bands)
```

The new set answers from the next round on. A round that is already out - and its
retry - belongs to the bands it was asked of, so a swap never cuts a round in
half, and nothing waits for the caller because the swap happens when that round
closes. What a swap may change is who answers for the columns, not which columns
the pooler expects: a band set that does not cover the population is not refused
- an actor cannot refuse a message - and shows up in the answer's `missing`
instead.

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

- A retry is one more deadline, not a backoff. A shard that is busy twice is
  given up on for that round, and nothing distinguishes busy from stuck - one is
  a matter of when it answers, the other of whether.
- One pooler is one coordinator. Two poolers over the same shards would each
  start their own rounds.
- The temporal region has none of this: no deadline, so it waits for every shard
  on both passes, and no way to hand it new shards. A prediction needs all of
  them, so there is nothing to decide without the missing shard - which is why
  the pooler's retry would not help it as it stands.
