interface ClaObserver
  """
  Whoever asked a pooler for a step, and so receives the answer.
  """
  be observed(output: ClaOutput val)

actor TemporalPoolerActor
  """
  The CLA temporal pooler as an actor: steps arrive as messages and each answer
  goes to whoever asked for it.

  One actor, not a set of shards, and that is the difference from
  `TemporalRegion`. A temporal memory's segments reach cells of their own column
  only, so its columns can be split between shards that never write to the same
  one. A pooler's segments reach the whole population - a segment sits on a cell
  of one node and its synapses reach cells of many - so any split would either
  copy the state or let two actors learn from it at once. One actor owns the
  pooler, and that is why.

  Messages are answered in the order they arrive, which is what makes this a
  sequence of steps rather than a set of independent ones. A `reset` is ordered
  with the steps of whoever sent it and with nothing else, so the sender that
  ends a training sequence has to be the one that sent it.

  Asked for neither learning nor inferring it does not step, and answers with
  the state as it stands: an actor cannot refuse a message, and the answer says
  what is true rather than pretending a step happened.
  """
  let _pooler: TemporalPooler

  new create(config: TemporalPoolerConfig val, seed: U64 = 42) =>
    _pooler = TemporalPooler(config, seed)

  be compute(
    columns: Array[USize] val,
    learn: Bool,
    infer: Bool,
    asker: ClaObserver tag)
  =>
    """
    Read one step's input and answer the asker with what it produced.
    """
    try _pooler.compute(columns, learn, infer)? end
    asker.observed(_pooler.answer())

  be reset() =>
    """
    Forget the situation, keeping what has been learned.

    Answers nobody: a reset has nothing to say about a step, and the next step
    says it.
    """
    _pooler.reset()
