use "pony_test"
use "time"
use "../htm"

class BallotBoxTest is TestList
  fun name(): String => "Ballot box"

  fun tag tests(test: PonyTest) =>
    test(_EveryVoteCompletesTheRound)
    test(_AQuorumAnswersWithoutTheSlowColumns)
    test(_TheDeadlineAnswersWithWhatArrived)
    test(_AStragglerCannotAnswerTwice)

class Settle is TimerNotify
  let _recorder: Recorder

  new iso create(recorder: Recorder) =>
    _recorder = recorder

  fun ref apply(timer: Timer, count: U64): Bool =>
    _recorder.settle()
    false

actor Recorder is Tally
  """
  Waits a moment after the first answer, so a second answer would be caught
  rather than hidden by the test finishing first.
  """
  let _h: TestHelper
  let _expected: USize
  var _answered: USize = 0
  var _votes: USize = 0
  let _timers: Timers = Timers

  new create(h: TestHelper, expected: USize) =>
    _h = h
    _expected = expected

  be tallied(votes: Array[Vote] iso) =>
    _answered = _answered + 1
    let received: Array[Vote] val = consume votes

    if _answered == 1 then
      _votes = received.size()
      _timers(Timer(Settle(this), 30_000_000))
    end

  be settle() =>
    _h.assert_eq[USize](1, _answered, "the question should be answered exactly once")
    _h.assert_eq[USize](_expected, _votes, "votes in the answer")
    _h.complete(true)

class iso _EveryVoteCompletesTheRound is UnitTest
  fun name(): String => "the round is answered once every column has voted"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let ballot = BallotBox(Recorder(h, 3), 3)

    ballot.vote(Vote(0, 0.4)); ballot.vote(Vote(1, 0.7)); ballot.vote(Vote(2, 0.1))

class iso _AQuorumAnswersWithoutTheSlowColumns is UnitTest
  fun name(): String => "a quorum answers without waiting for the slow columns"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let ballot = BallotBox(Recorder(h, 2), 5, 2)

    ballot.vote(Vote(0, 0.4)); ballot.vote(Vote(1, 0.7))
    // the round is already answered; this one must not reach the tally
    ballot.vote(Vote(2, 0.1))

class iso _TheDeadlineAnswersWithWhatArrived is UnitTest
  fun name(): String => "the deadline answers with whatever arrived in time"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let ballot = BallotBox(Recorder(h, 1), 5, 5, 50)

    ballot.vote(Vote(0, 0.4))

class iso _AStragglerCannotAnswerTwice is UnitTest
  fun name(): String => "a vote after the round is decided is dropped"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let ballot = BallotBox(Recorder(h, 2), 2)

    ballot.vote(Vote(0, 0.4)); ballot.vote(Vote(1, 0.7))
    ballot.vote(Vote(2, 0.9))
