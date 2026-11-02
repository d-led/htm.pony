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
    test(_TheBoxNamesTheBandsThatNeverReported)

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
  let _silent: USize
  var _answered: USize = 0
  var _votes: USize = 0
  var _quiet: USize = 0
  let _timers: Timers = Timers

  new create(h: TestHelper, expected: USize, silent: USize = 0) =>
    _h = h
    _expected = expected
    _silent = silent

  be tallied(votes: Array[Vote] iso, silent: Array[USize] val) =>
    _answered = _answered + 1
    let received: Array[Vote] val = consume votes

    if _answered == 1 then
      _votes = received.size()
      _quiet = silent.size()
      _timers(Timer(Settle(this), 100_000_000))
    end

  be settle() =>
    _h.assert_eq[USize](1, _answered, "the question should be answered exactly once")
    _h.assert_eq[USize](_expected, _votes, "votes in the answer")
    _h.assert_eq[USize](_silent, _quiet, "bands that never reported")
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
    // a deadline with room to spare: the vote below arrives at once, so what
    // this measures is that a deadline answers without one, not how quick the
    // machine is
    let ballot = BallotBox(Recorder(h, 1), 5, 5, 250)

    ballot.vote(Vote(0, 0.4))

class iso _AStragglerCannotAnswerTwice is UnitTest
  fun name(): String => "a vote after the round is decided is dropped"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let ballot = BallotBox(Recorder(h, 2), 2)

    ballot.vote(Vote(0, 0.4)); ballot.vote(Vote(1, 0.7))
    ballot.vote(Vote(2, 0.9))

class iso _TheBoxNamesTheBandsThatNeverReported is UnitTest
  fun name(): String => "a box told who to expect names the bands that stayed silent"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)

    let expected: Array[USize] val = recover val [0; 1; 2] end
    let ballot = BallotBox(Recorder(h, 2, 1), 3, 2, 0, expected)

    let first: Array[Vote] iso = recover iso [Vote(0, 0.4)] end
    let second: Array[Vote] iso = recover iso [Vote(1, 0.7)] end
    ballot.cast(0, consume first)
    ballot.cast(1, consume second)
