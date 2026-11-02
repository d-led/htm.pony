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

  `silent` names the bands that were asked and had not reported when the round
  closed. A tally that can tell its bands apart can ask those again; one that
  cannot may ignore it.
  """
  be tallied(votes: Array[Vote] iso, silent: Array[USize] val)

interface Ballot
  """
  Where votes go during a round.

  Columns push into this shape and never name the collector, so neither side
  depends on the other's type and a shard can be tested against any sink.

  A band that owns several columns reports them in one `cast` and names itself,
  which is how the collector can tell a band that answered from one that never
  spoke.
  """
  be vote(vote': Vote)
  be cast(band: USize, votes: Array[Vote] iso)

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

  Given the bands it should hear from, it also says which of them stayed
  silent - that is what lets a pooler ask a slow band again instead of deciding
  without it. Without a roster it only counts votes.
  """
  let _tally: Tally tag
  let _timers: Timers
  let _bands: Array[USize] val
  let _answered: Set[USize] = Set[USize]
  let _expected: USize
  let _quorum: USize
  let _votes: Array[Vote] = Array[Vote]
  var _arrived: USize = 0
  var _decided: Bool = false

  new create(
    tally: Tally tag,
    expected: USize,
    quorum: USize = 0,
    deadline_ms: U64 = 0,
    bands: Array[USize] val = [])
  =>
    _tally = tally
    _expected = expected
    _bands = bands

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

  be cast(band: USize, votes: Array[Vote] iso) =>
    """
    A whole band's votes in one message. Each vote counts towards the quorum,
    so the caller's numbers stay in votes however the columns are grouped.
    """
    if _decided then return end

    _answered.set(band)
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

    let silent: Array[USize] iso = recover iso Array[USize] end
    for band in _bands.values() do
      if not _answered.contains(band) then
        silent.push(band)
      end
    end

    _tally.tallied(consume answer, consume silent)

class Deadline is TimerNotify
  let _box: BallotBox

  new iso create(owner: BallotBox) =>
    _box = owner

  fun ref apply(timer: Timer, count: U64): Bool =>
    _box.deadline_reached()
    // one deadline per question
    false
