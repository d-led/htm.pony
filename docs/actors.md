# Actors

The spatial pooler also runs as messages. The computation does not change: the
same wiring, the same overlap, the same inhibition. What changes is where it
runs and how the answer travels.

The actor path exists so that columns can be spread across cores, and so that a
slow or absent column cannot hold up a round.

## The shape of the path

```text
Asker        --represent(active, asker)-->   Pooler
Pooler       --observe(active, ballot)-->    ColumnShard, once per shard
ColumnShard  --cast(votes)-->                BallotBox
BallotBox    --tallied(votes)-->             Pooler
Pooler       --represented(winners)-->       Asker
```

No step returns a value. The asker hands over a `Representation` and the answer
arrives at `represented` when the round closes. That is what lets a round be in
flight while the caller does something else.

## Three interfaces and nothing else

The actors do not name each other's types:

```pony
interface Ballot
  be vote(vote': Vote)
  be cast(votes: Array[Vote] iso)

interface Tally
  be tallied(votes: Array[Vote] iso)

interface Representation
  be represented(active: Array[USize] iso)
```

A column pushes into a `Ballot` and never learns what collects the votes. The
ballot box pushes into a `Tally` and never learns what asked. An asker
implements `Representation` and is handed the answer.

The practical effect is that a shard can be tested against any sink, and a sink
against any source. `test/column_shard_test.pony` and `test/ballot_box_test.pony`
do exactly that.

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

## Columns and shards

`CorticalColumn` is one column answering on its own:

```pony
be observe(active: Array[Bool] val, ballot: Ballot tag) =>
  let overlap = Synapses.overlap(_synapses, active, _threshold)
  ballot.vote(Vote(_index, overlap.f64()))
```

`ColumnShard` is a band of columns sharing one actor:

```pony
actor ColumnShard
  let _columns: Array[ColumnView] val
  let _threshold: F64

  be observe(active: Array[Bool] val, ballot: Ballot tag) =>
    let votes: Array[Vote] iso = recover iso Array[Vote] end
    for column in _columns.values() do
      let overlap = Synapses.overlap(column.synapses, active, _threshold)
      votes.push(Vote(column.index, overlap.f64()))
    end
    ballot.cast(consume votes)
```

One actor per column costs a message in and a message out for every column. A
shard costs that once for the whole band and reports its votes in a single
message. The ballot box still counts votes, not messages, so grouping columns
does not change when a round closes.

Both take `Array[Synapse] val`, and neither validates the wiring at
construction: an actor constructor cannot fail, so there is no place to report a
connection that reaches past the end of the input. The pooler settles the input
width first and hands over synapses that fit. `Synapses.overlap` skips anything
that does not, which is the backstop rather than the rule.

## The coordinator

`Pooler` is the actor that asks and answers.

```pony
let pooler = Pooler(shards, Grid([8; 8])?, config)
pooler.represent(active, asker)
```

It runs one round at a time. A second request waits in a queue rather than
overwriting a tally still in flight:

```pony
be represent(active: Array[Bool] val, asker: Representation tag) =>
  _queue.push(Round(active, asker))
  _pump()
```

When the tally arrives it inhibits the votes and pushes the winners to the
asker, then takes the next request.

The ballots it creates expect one vote per column and set the quorum to the same
number. A deadline is not set, so a shard that never answers holds the round
open. Setting one is a change to `_pump`, and the ballot box already supports it.

## Ordering and ties

Votes are stored in the order they arrive, which is not the column order. The
inhibition stage rebuilds the overlaps into a column-indexed array before
deciding, so arrival order cannot change the representation.

`tallied` reports the winners to `represented` in whatever order inhibition
produced them, which is ascending column order in both modes.

## What is missing

- No retry when a shard does not answer, and no way to tell a slow shard from a
  dead one. A deadline would close the round but the pooler does not set one.
- No way to add or remove a shard while the pooler is running.
- No supervision: an actor that crashes is gone, and the pooler waits.
- One pooler is one coordinator. Two poolers over the same shards would each
  start their own rounds.
