class val Duration is (Equatable[Duration] & Stringable)

  let _seconds: I64 val
  let _nanos: U32 val

  new val create(seconds: I64 val = 0, nanos: U32 val = 0) =>
    _seconds = seconds
    _nanos = nanos

  new val from_millis(millis: I64 val) =>
    let nanos_adjustment = millis % MillisPerSecond().i64()
    if nanos_adjustment < 0 then
      _seconds = (millis / MillisPerSecond().i64()) - 1
      _nanos = (nanos_adjustment + MillisPerSecond().i64()).u32() * NanosPerMilli().u32()
    else
      _seconds = millis / MillisPerSecond().i64()
      _nanos = nanos_adjustment.u32() * NanosPerMilli().u32()
    end

  new val _create(seconds: I64 val, nanos: I64 val) =>
    if nanos >= 0 then
      _seconds = seconds
      _nanos = (nanos % NanosPerSecond().i64()).u32()
    else
      _seconds = seconds - 1
      _nanos = (NanosPerSecond().i64() + (nanos % NanosPerSecond().i64())).u32()
    end

  fun get_seconds(): I64 val =>
    _seconds

  fun get_nanos(): U32 val =>
    _nanos

  fun to_millis(): I64 val =>
    let nanos_in_millis: I64 = _nanos.i64() / NanosPerMilli().i64()
    if (_seconds < 0) and (_nanos != 0) then
        let millis: I64 = (_seconds + 1).i64() * MillisPerSecond().i64()
        let adjustment: I64 = nanos_in_millis.i64() - MillisPerSecond().i64()
        millis + adjustment
    else
        let millis: I64 = _seconds.i64() * MillisPerSecond().i64()
        millis + nanos_in_millis
    end

  fun val add(that: Duration val): Duration val =>
    add_seconds_and_nanos(that.get_seconds(), that.get_nanos().i64())

  fun val sub(that: Duration val): Duration val =>
    sub_seconds_and_nanos(that.get_seconds(), that.get_nanos().i64())

  fun val sub_seconds_and_nanos(seconds: I64, nanos: I64): Duration val =>
    add_seconds_and_nanos(-1 * seconds, -1 * nanos)

  fun val add_seconds_and_nanos(seconds: I64, nanos: I64): Duration val =>
    if (seconds != 0) or (nanos != 0) then
      let nanos_sum = get_nanos().i64() + nanos
      let seconds_in_nanos = nanos_sum / NanosPerSecond().i64()
      let seconds_sum = get_seconds().i64() + seconds.i64() + seconds_in_nanos
      Duration._create(seconds_sum, nanos_sum)
    else
      this
    end

  fun box eq(that: Duration box): Bool val =>
    (this.get_seconds() == that.get_seconds())
    and (this.get_nanos() == that.get_nanos())

  fun string(): String iso^ =>
    String.join([
      "Instance of "
      get_seconds().string()
      " seconds and "
      get_nanos().string()
      " nanoseconds."
    ].values())
