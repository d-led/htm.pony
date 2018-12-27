use "format"

class val LocalTime is (Equatable[LocalTime] & Stringable)

  let _hours: I32 val
  let _minutes: I32 val
  let _seconds: I32 val
  let _nanos: I32 val

  new val from_nano_of_day(nanos_of_day: I64) =>
    //@printf[I32](("nanos_of_day " + nanos_of_day.string() + "\n").cstring())
    var nanos = nanos_of_day
    _hours = (nanos.u64() / NanosPerHour()).i32()
    nanos = nanos - (_hours.i64() * NanosPerHour().i64())
    _minutes = (nanos / NanosPerMinute().i64()).i32()
    nanos = nanos - (_minutes.i64() * NanosPerMinute().i64())
    _seconds = (nanos / NanosPerSecond().i64()).i32()
    _nanos = (nanos - (_seconds.i64() * NanosPerSecond().i64())).i32()

  new val create(hours: I32 val, minutes: I32 val, seconds: I32 val, nanos: I32 val) =>
    _hours = hours
    _minutes = minutes
    _seconds = seconds
    _nanos = nanos

  fun get_hours(): I32 =>
    _hours

  fun get_minutes(): I32 =>
    _minutes

  fun get_seconds(): I32 =>
    _seconds

  fun get_nanos(): I32 =>
    _nanos

  fun box eq(that: LocalTime box): Bool val =>
    (this.get_hours() == that.get_hours())
    and (this.get_minutes() == that.get_minutes())
    and (this.get_seconds() == that.get_seconds())
    and (this.get_nanos() == that.get_nanos())

  fun string(): String iso^ =>
    String.join([
      Format.int[I32](get_hours() where width = 2, fill='0')
      ":"
      Format.int[I32](get_minutes() where width = 2, fill='0')
      ":"
      Format.int[I32](get_seconds() where width = 2, fill='0')
      "."
      Format.int[I32](get_nanos() / NanosPerMilli().i32() where width = 3, fill='0')
    ].values())
