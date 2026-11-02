class ClaSegment
  """
  One cell's memory of the situation that came before it, and how good a
  predictor it has turned out to be.

  Two questions are asked of a segment, and they are different questions. Its
  *activity* is how many of its synapses reach cells that are active right now,
  however weak those synapses are - the reference calls that a weak match, and it
  is what a column looks at when it wonders whether a segment is worth learning
  on. It is *active* only when enough of those synapses have been learned past
  the connection threshold, and an active segment is a prediction.

  A segment also keeps a running estimate of how often it has been right. The
  reference computes it in tiers: while there is little history the estimate is
  simply right-over-steps, and once there is enough it becomes a moving average
  whose step is chosen by how long the segment has lived. `duty_cycle` walks the
  cache forward on demand, so a caller has to ask about every segment at each
  tier boundary or the tier it was last asked at is the one it still uses.
  """
  var synapses: Array[TemporalSynapse]
  var last_active: U64
  var positive: USize
  var total: USize
  var _duty_cycle: F64
  var _duty_cycle_at: U64

  new create(iteration: U64) =>
    """
    A segment born at this step. It starts with one activation recorded - its
    own creation - which is the reference's choice and keeps a brand new segment
    from reading as a predictor that has always been wrong.

    The reference derives the starting duty cycle as one over the iteration, and
    so divides by zero at iteration zero. Here that case starts at one, because
    an infinity would be carried into every confidence it is added to.
    """
    synapses = Array[TemporalSynapse]
    last_active = iteration
    positive = 1
    total = 1
    _duty_cycle = if iteration == 0 then 1.0 else 1.0 / iteration.f64() end
    _duty_cycle_at = iteration

  fun activity(state: ReadSeq[Bool]): USize =>
    """
    How many of this segment's synapses reach a cell that is active now,
    connected or not.

    The reference can restrict this to connected synapses; every call it makes
    passes false, so the restriction is not carried over.
    """
    var count: USize = 0
    for synapse in synapses.values() do
      try
        if state(synapse.source)? then count = count + 1 end
      end
    end
    count

  fun active(
    state: ReadSeq[Bool],
    activation_threshold: USize,
    connected_threshold: F64): Bool
  =>
    """
    Whether this segment predicts: enough of its connected synapses reach cells
    that are active now.

    A segment with fewer synapses than the threshold cannot reach it, so it is
    turned away before any of them are read.
    """
    if synapses.size() < activation_threshold then return false end

    var count: USize = 0
    for synapse in synapses.values() do
      if not synapse.connected(connected_threshold) then continue end
      try
        if state(synapse.source)? then
          count = count + 1
          if count >= activation_threshold then return true end
        end
      end
    end
    false

  fun ref add_synapse(source: USize, permanence: F64) =>
    """
    Reach one more cell. A cell this segment already reaches is left alone
    rather than connected twice.
    """
    if reaches(source) then return end
    synapses.push(TemporalSynapse(source, permanence))

  fun reaches(source: USize): Bool =>
    """
    Whether this segment already has a synapse onto that cell.
    """
    for synapse in synapses.values() do
      if synapse.source == source then return true end
    end
    false

  fun age(iteration: U64): U64 =>
    """
    How many steps have passed since this segment last learned something.
    """
    iteration - last_active

  fun ref duty_cycle(iteration: U64, good: Bool): F64 =>
    """
    How often this segment has been a useful predictor, brought up to date for
    this iteration and for whether it was `good` this time.

    Asking again at the same iteration and without a good hit answers what was
    answered then, which is what lets a caller read it in a loop.
    """
    if iteration == 0 then return _duty_cycle end

    if iteration <= ClaDutyCycle.current_until() then
      _duty_cycle = positive.f64() / iteration.f64()
      _duty_cycle_at = iteration
      return _duty_cycle
    end

    let since = iteration - _duty_cycle_at
    if (since == 0) and not good then return _duty_cycle end

    let alpha = ClaDutyCycle.step(iteration)
    var estimate = (1.0 - alpha).pow(since.f64()) * _duty_cycle
    if good then estimate = estimate + alpha end

    _duty_cycle = estimate
    _duty_cycle_at = iteration
    estimate

  fun ref renew(iteration: U64) =>
    """
    Record that this segment's prediction came true: it is fresh again, and its
    estimate of how often it is right takes one step of good news.
    """
    last_active = iteration
    positive = positive + 1
    duty_cycle(iteration, true)

  fun ref move(indices: ReadSeq[USize], delta: F64, ceiling: F64): Bool =>
    """
    Move the permanence of the named synapses, holding them between zero and the
    ceiling. Answers whether any of them reached zero, which is the segment's cue
    that it has something to forget.
    """
    var reached_zero = false

    for index in indices.values() do
      try
        let synapse = synapses(index)?
        let moved =
          if delta >= 0.0 then
            let risen = synapse.permanence + delta
            if risen > ceiling then ceiling else risen end
          else
            let fallen = synapse.permanence + delta
            if fallen <= 0.0 then
              reached_zero = true
              0.0
            else
              fallen
            end
          end
        synapse.permanence = moved
      end
    end

    reached_zero

  fun ref drop_weak(min_permanence: F64) =>
    """
    Forget the synapses that have decayed below `min_permanence`. A segment that
    loses all of them is nothing but a memory of having been wrong.
    """
    var kept = Array[TemporalSynapse](synapses.size())
    for synapse in synapses.values() do
      if synapse.permanence >= min_permanence then kept.push(synapse) end
    end
    synapses = kept

  fun ref decay(amount: F64) =>
    """
    Age every synapse by `amount`, forgetting the ones that no longer reach
    anything at all.
    """
    var kept = Array[TemporalSynapse](synapses.size())
    for synapse in synapses.values() do
      synapse.permanence = synapse.permanence - amount
      if synapse.permanence > 0.0 then kept.push(synapse) end
    end
    synapses = kept

primitive ClaDutyCycle
  """
  The tiers the reference moves between when it turns a segment's record into a
  running estimate.

  With little history a fraction is exact enough; after that the estimate is a
  moving average, and the larger the history the smaller the step it moves by.
  The step also has to be recomputed at each boundary or a segment that is never
  asked again keeps the step it was born with.
  """

  fun current_until(): U64 =>
    """
    The last iteration that still uses the plain fraction.
    """
    100

  fun is_a_boundary(iteration: U64): Bool =>
    """
    Whether this iteration is where the step changes. Every segment has to be
    brought up to date at each of these or it keeps the step it was last asked
    with.
    """
    (iteration == 100) or (iteration == 320) or (iteration == 1000) or
      (iteration == 3200) or (iteration == 10000) or (iteration == 32000) or
      (iteration == 100000) or (iteration == 320000)

  fun step(iteration: U64): F64 =>
    """
    How much of a new result the moving average takes at this iteration. Zero
    below the first tier, where the fraction is used instead.
    """
    if iteration > 320000 then 0.0000010
    elseif iteration > 100000 then 0.0000032
    elseif iteration > 32000 then 0.00001
    elseif iteration > 10000 then 0.000032
    elseif iteration > 3200 then 0.00010
    elseif iteration > 1000 then 0.00032
    elseif iteration > 320 then 0.0010
    elseif iteration > 100 then 0.0032
    else 0.0 end
