use "pony_test"
use "../htm"

// The claim, as for every actor form here: the same steps answered by actors
// give the same answer as the pooler in process.

class TemporalPoolerActorTest is TestList
  fun name(): String => "CLA temporal pooler, as an actor"

  fun tag tests(test: PonyTest) =>
    test(_APoolerActorAnswersWhatOneProcessAnswers)
    test(_APoolerActorForecastsWhatOneProcessForecasts)
    test(_AStepThatAsksForNothingAnswersWhatIsThere)
    test(_AResetOnTheActorEndsTheSequence)

actor IgnoringObserver is ClaObserver
  """
  Asks for steps whose answers nobody looks at, which is how a training
  sequence is sent.
  """
  be observed(output: ClaOutput val) => None

actor ClaComparingObserver is ClaObserver
  """
  Compares each answer with what one process said about the same step.
  """
  let _h: TestHelper
  let _expected: Array[ClaOutput val] val
  var _seen: USize = 0
  var _matching: USize = 0

  new create(h: TestHelper, expected: Array[ClaOutput val] val) =>
    _h = h
    _expected = expected

  be observed(output: ClaOutput val) =>
    try
      let wanted = _expected(_seen)?
      if
        _same(output.output_cells, wanted.output_cells)
          and _same(output.active_cells, wanted.active_cells)
          and _same(output.predictive_cells, wanted.predictive_cells)
          and _same(output.predicted_nodes, wanted.predicted_nodes)
          and _same_confidences(output.node_confidences, wanted.node_confidences)
      then
        _matching = _matching + 1
      end
    end

    _seen = _seen + 1
    if _seen == _expected.size() then
      _h.assert_eq[USize](
        _expected.size(),
        _matching,
        "every step should match the one-process answer")
      _h.complete(true)
    end

  fun _same(left: ReadSeq[USize], right: ReadSeq[USize]): Bool =>
    if left.size() != right.size() then return false end
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? != right(index)? then return false end
        index = index + 1
      end
      true
    else
      false
    end

  fun _same_confidences(left: ReadSeq[F64], right: ReadSeq[F64]): Bool =>
    if left.size() != right.size() then return false end
    try
      var index: USize = 0
      while index < left.size() do
        if left(index)? != right(index)? then return false end
        index = index + 1
      end
      true
    else
      false
    end

actor NothingAskedObserver is ClaObserver
  """
  Checks that a step asking for neither learning nor inferring answers with the
  state the pooler already had.
  """
  let _h: TestHelper
  let _active_before: Array[USize] val

  new create(h: TestHelper, active_before: Array[USize] val) =>
    _h = h
    _active_before = active_before

  be observed(output: ClaOutput val) =>
    _h.assert_array_eq[USize](
      _active_before, output.active_cells,
      "nothing was asked for, so nothing stepped")
    _h.assert_eq[USize](
      0, output.predictive_cells.size(), "and nothing could be predicted")
    _h.complete(true)

actor ResetObserver is ClaObserver
  """
  Checks the step after a reset: every node it sees is on its start cell.
  """
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be observed(output: ClaOutput val) =>
    let active = output.active_cells
    _h.assert_eq[USize](10, active.size(), "one cell a node")
    for cell in active.values() do
      _h.assert_eq[USize](0, cell % 2, "and it is the start cell")
    end
    _h.complete(true)

actor ComparingForecast is ClaForecaster
  """
  Compares a forecast with what the pooler in process said about the same state.
  """
  let _h: TestHelper
  let _expected: ClaForecast

  new create(h: TestHelper, expected: ClaForecast) =>
    _h = h
    _expected = expected

  be forecasted(forecast: ClaForecast val) =>
    _h.assert_eq[USize](
      _expected.size(), forecast.size(), "the forecast reaches as far")
    try
      var step: USize = 0
      while step < _expected.size() do
        _h.assert_array_eq[USize](
          _expected.nodes(step)?,
          forecast.nodes(step)?,
          "the nodes at step " + (step + 1).string())
        step = step + 1
      end
    end
    _h.complete(true)

class iso _APoolerActorAnswersWhatOneProcessAnswers is UnitTest
  fun name(): String => "the same steps give the same answers on actors"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let config = Patterns.config()?

    // learned and asked in process, for what each step should say
    let expected: Array[ClaOutput val] val = recover val
      let pooler = TemporalPooler(config, 7)
      var epoch: USize = 0
      while epoch < 5 do
        var index: USize = 0
        while index < 5 do
          pooler.compute(Patterns.of(index), true, false)?
          index = index + 1
        end
        pooler.reset()
        epoch = epoch + 1
      end

      let answers = Array[ClaOutput val]
      var step: USize = 0
      while step < 4 do
        pooler.compute(Patterns.of(step), false, true)?
        answers.push(pooler.answer())
        step = step + 1
      end
      answers
    end

    // the same steps, sent to the actor
    let subject = TemporalPoolerActor(config, 7)
    let ignoring = IgnoringObserver

    var epoch: USize = 0
    while epoch < 5 do
      var index: USize = 0
      while index < 5 do
        subject.compute(Patterns.of_value(index), true, false, ignoring)
        index = index + 1
      end
      subject.reset()
      epoch = epoch + 1
    end

    let observer = ClaComparingObserver(h, expected)
    var step: USize = 0
    while step < 4 do
      subject.compute(Patterns.of_value(step), false, true, observer)
      step = step + 1
    end

class iso _APoolerActorForecastsWhatOneProcessForecasts is UnitTest
  fun name(): String => "a forecast on the actor names what one process names"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let config = Patterns.config()?
    let in_process = TemporalPooler(config, 7)
    let subject = TemporalPoolerActor(config, 7)
    let ignoring = IgnoringObserver

    // the same teaching, to a pooler in process and to the actor
    var epoch: USize = 0
    while epoch < 5 do
      var index: USize = 0
      while index < 5 do
        in_process.compute(Patterns.of(index), true, false)?
        subject.compute(Patterns.of_value(index), true, false, ignoring)
        index = index + 1
      end
      in_process.reset()
      subject.reset()
      epoch = epoch + 1
    end

    // both read the same pattern, so both forecast from the same state
    in_process.compute(Patterns.of(0), false, true)?
    subject.compute(Patterns.of_value(0), false, true, ignoring)

    subject.predict(3, ComparingForecast(h, in_process.predict(3)?))

class iso _AStepThatAsksForNothingAnswersWhatIsThere is UnitTest
  fun name(): String =>
    "a step that asks for neither learning nor inferring does nothing"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let pooler = Patterns.pooler()?
    pooler.compute(Patterns.of(0), false, true)?
    let active = pooler.active_cells()

    let subject = TemporalPoolerActor(Patterns.config()?, 7)
    subject.compute(Patterns.of_value(0), false, true, IgnoringObserver)
    subject.compute(
      Patterns.of_value(1), false, false, NothingAskedObserver(h, active))

class iso _AResetOnTheActorEndsTheSequence is UnitTest
  fun name(): String => "a reset sent to the actor starts the next step on start cells"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let subject = TemporalPoolerActor(Patterns.config()?, 7)
    let ignoring = IgnoringObserver

    // learn the cycle, then begin again and ask for a pattern in the middle
    var epoch: USize = 0
    while epoch < 2 do
      var index: USize = 0
      while index < 5 do
        subject.compute(Patterns.of_value(index), true, false, ignoring)
        index = index + 1
      end
      subject.reset()
      epoch = epoch + 1
    end

    subject.compute(Patterns.of_value(2), false, true, ResetObserver(h))
