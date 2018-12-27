class val Instant is (Equatable[Instant] & Stringable)

  /** Duration since 1970-01-01:00:00:00 */
  let _duration : Duration val

  new val create(seconds: I64 val, nanos: U32 val) =>
    _duration = Duration(seconds, nanos)

  new val from_millis(millis: I64 val) =>
    _duration = Duration.from_millis(millis)

  new val from_duration(data: Duration val) =>
    _duration = data

  new val now(clock: Clock val = SystemClock) =>
    let n = clock.now()
    _duration = Duration(n._1, n._2)

  fun string(): String iso^ =>
    String.join([
      "Instance of "
      get_seconds().string()
      " seconds and "
      get_nanos().string()
      " nanoseconds since 1970-01-01T00:00:00Z."
    ].values())

  fun get_seconds(): I64 val =>
    _duration.get_seconds()

  fun get_nanos(): U32 val =>
    _duration.get_nanos()

  fun to_millis(): I64 val =>
    _duration.to_millis()

  fun val add_seconds_and_nanos(seconds: I64 val, nanos: I64 val): Instant val =>
    if (seconds != 0) or (nanos != 0) then
      Instant.from_duration(_duration.add_seconds_and_nanos(seconds, nanos))
    else
      this
    end

  fun val add(duration: Duration val): Instant val =>
    add_seconds_and_nanos(duration.get_seconds(), duration.get_nanos().i64())

  fun val sub(duration: Duration val): Instant val =>
    add_seconds_and_nanos(-duration.get_seconds(), -duration.get_nanos().i64())

  fun val sub_seconds_and_nanos(seconds: I64, nanos: I64): Instant val =>
    add_seconds_and_nanos(-seconds, -nanos)

  fun box eq(that: Instant box): Bool val =>
    (this.get_seconds() == that.get_seconds())
    and (this.get_nanos() == that.get_nanos())
