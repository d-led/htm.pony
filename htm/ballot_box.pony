use "collections"
use "time"

class val Vote
  """
  One column's answer to one question: what it recognises, and how strongly.
  """
  let column: USize
  let overlap: F64

  new val create(column': USize, overlap': F64) =>
    column = column'
    overlap = overlap'

interface Tally
  """
  Whoever asked the question, and so receives the answer.
  """
  be tallied(votes: Array[Vote] iso)

interface Ballot
  """
  Where votes go during a round.

  Columns push into this shape and never name the collector, so neither side
  depends on the other's type and a shard can be tested against any sink.
  """
  be vote(vote': Vote)
  be cast(votes: Array[Vote] iso)

actor BallotBox is Ballot
  """
  Collects the columns' votes on one question.

  The round is over as soon as any of these happens, whichever comes first:

  * every expected vote has arrived
  * a predefined number of votes has arrived - a quorum, so a few slow
    columns cannot hold up the answer
  * the deadline expires

  A vote that arrives after the round is decided is dropped, so a straggler
  cannot deliver a second answer to the same question.
  """
  let _tally: Tally tag
  let _timers: Timers
  var _expected: USize
  var _quorum: USize
  var _arrived: USize = 0
  var _decided: Bool = false
  var _votes: Array[Vote] = Array[Vote]

  new create(tally: Tally tag, expected: USize, quorum: USize = 0, deadline_ms: U64 = 0) =>
    _tally = tally
    _expected = expected

    // asking for more votes than exist would wait forever, and a quorum of
    // zero would answer an empty question straight away
    _quorum =
      if (quorum == 0) or (quorum > expected) then expected else quorum end

    _timers = Timers
    if deadline_ms > 0 then
      _timers(Timer(Deadline(this), deadline_ms * 1_000_000))
    end

  be vote(vote': Vote) =>
    if _decided then return end

    _votes.push(vote')
    _arrived = _arrived + 1

    if (_arrived >= _quorum) or (_arrived >= _expected) then
      _decide()
    end

  be cast(votes: Array[Vote] iso) =>
    """
    A whole shard's votes in one message. Each vote counts towards the quorum,
    so the caller's numbers stay in votes however the columns are grouped.
    """
    if _decided then return end

    let received: Array[Vote] val = consume votes
    for one in received.values() do
      _votes.push(one)
    end
    _arrived = _arrived + received.size()

    if (_arrived >= _quorum) or (_arrived >= _expected) then
      _decide()
    end

  be deadline_reached() =>
    if _decided then return end
    _decide()

  fun ref _decide() =>
    _decided = true

    let answer: Array[Vote] iso = recover iso Array[Vote] end
    for one in _votes.values() do
      answer.push(one)
    end
    _tally.tallied(consume answer)

class Deadline is TimerNotify
  let _box: BallotBox

  new iso create(owner: BallotBox) =>
    _box = owner

  fun ref apply(timer: Timer, count: U64): Bool =>
    _box.deadline_reached()
    // one deadline per question
    false
