use "collections"

interface AnomalyObserver
  """
  Whoever asked for a step, and so receives the reading.

  `score` is the share of this step's columns the memory did not predict;
  `likelihood` is where that score falls among the scores before it. They answer
  different questions - one is about this step, the other about how unusual such
  a step is - and neither is the whole answer alone.
  """
  be scored(score: F64, likelihood: F64)

class val AnomalyStep
  """
  One input waiting to be scored.
  """
  let input: Array[Bool] val
  let learn: Bool
  let asker: AnomalyObserver tag

  new val create(
    input': Array[Bool] val,
    learn': Bool,
    asker': AnomalyObserver tag)
  =>
    input = input'
    learn = learn'
    asker = asker'

actor AnomalyStream is (Representation & TemporalObserver)
  """
  The streaming anomaly score, on the actor path.

  Both halves already existed - a `Pooler` that turns an input into columns and a
  `TemporalRegion` that learns the order those columns arrive in - and nothing
  joined them. This is the join: it asks the pooler for a representation, hands
  the columns to the region, and scores what comes back with the share of them
  the memory did not expect. The likelihood of that score, given the scores
  before it, comes with it.

  The pooler is used as it was handed over, as in process: the memory predicts
  over the pooler's representation, so a representation that kept moving would
  move the thing being learned. A caller that wants the representation to adapt
  drives the pooler itself.

  One step is in flight at a time, and a step that arrives while another is
  running waits its turn rather than interleaving: a score is a statement about
  the step before it, so the order is part of the answer. A region that never
  hears from a band says so through `missing`, and that number is not passed on -
  the memory learns the columns the pooler agreed on, and a step decided without
  a band is what a deadline buys.
  """
  let _pooler: Pooler tag
  let _region: TemporalRegion tag
  let _params: TemporalMemoryParams val
  let _likelihood: AnomalyLikelihood

  var _queue: Array[AnomalyStep] = Array[AnomalyStep]
  var _in_flight: Bool = false
  var _asker: (AnomalyObserver tag | None) = None
  var _learn: Bool = false

  new create(
    pooler: Pooler tag,
    region: TemporalRegion tag,
    params: TemporalMemoryParams val,
    likelihood: AnomalyLikelihood iso)
  =>
    """
    The two halves and the memory's parameters - which are here to read a step's
    columns and cells back into a score, not to build anything.

    The likelihood arrives built and is taken over: it keeps a history and
    re-estimates a distribution over it, and one history has one owner, which is
    this actor. Building it at the call site is also where a bad set of periods
    is refused, which an actor constructor could not do.
    """
    _pooler = pooler
    _region = region
    _params = params
    _likelihood = consume likelihood

  be observe(
    input: Array[Bool] val,
    learn: Bool,
    asker: AnomalyObserver tag)
  =>
    """
    Fold one input into the model and answer how surprising it was.

    `learn` says whether the memory takes the step in; the pooler is not trained
    either way.
    """
    _queue.push(AnomalyStep(input, learn, asker))
    _pump()

  be represented(columns: Array[USize] iso, missing: USize) =>
    """
    The pooler's answer: the columns of this step.
    """
    _region.compute(consume columns, _learn, this)

  be observed(output: TemporalOutput val) =>
    let score = output.anomaly(_params)
    let likelihood = try _likelihood.observe(score)? else 0.0 end
    let asker = _asker

    _asker = None
    _in_flight = false

    match asker
    | let who: AnomalyObserver tag => who.scored(score, likelihood)
    end

    _pump()

  fun ref _pump() =>
    if _in_flight then return end

    match _take()
    | let step: AnomalyStep =>
      _in_flight = true
      _asker = step.asker
      _learn = step.learn
      _pooler.represent(step.input, false, this)
    end

  fun ref _take(): (AnomalyStep | None) =>
    if _queue.size() == 0 then return None end
    try _queue.shift()? else None end
