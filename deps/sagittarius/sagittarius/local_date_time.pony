class val LocalDateTime is (Equatable[LocalDateTime] & Stringable)

  let _date: LocalDate val
  let _time: LocalTime val

  new val from_millis(millis: I64 val) =>
    let instant = Instant.from_millis(millis)
    let d = _create_date_and_time(instant.get_seconds().i64(), instant.get_nanos())
    _date = d._1
    _time = d._2

  new val from_instant(instant: Instant) =>
    let d = _create_date_and_time(instant.get_seconds().i64(), instant.get_nanos())
    _date = d._1
    _time = d._2

  new val from_epoch_seconds(seconds: I64 = 0, nanos: U32 = 0) =>
    let d = _create_date_and_time(seconds, nanos)
    _date = d._1
    _time = d._2

  fun tag _create_date_and_time(seconds: I64, nanos: U32): (LocalDate, LocalTime) =>
    // @printf[I32](("seconds " + seconds.string() + "nanos " + nanos.string() + "\n").cstring())
    let days = seconds / SecondsPerDay().i64()
    let seconds_of_day = seconds % SecondsPerDay().i64()
    let nanos_of_day = (seconds_of_day * NanosPerSecond().i64()) + nanos.i64()
    (LocalDate.from_epoch_day(days), LocalTime.from_nano_of_day(nanos_of_day))

  fun get_years(): I32 =>
    _date.get_years()

  fun get_months(): I32 =>
    _date.get_months()

  fun get_days(): I32 =>
    _date.get_days()

  fun get_hours(): I32 =>
    _time.get_hours()

  fun get_minutes(): I32 =>
    _time.get_minutes()

  fun get_seconds(): I32 =>
    _time.get_seconds()

  fun get_nanos(): I32 =>
    _time.get_nanos()

  fun get_date(): LocalDate =>
    _date

  fun get_time(): LocalTime =>
    _time

  fun box eq(that: LocalDateTime box): Bool val =>
    (this.get_date() == that.get_date())
    and (this.get_time() == that.get_time())

  fun string(): String iso^ =>
    String.join([
      _date.string()
      "T"
      _time.string()
    ].values())
