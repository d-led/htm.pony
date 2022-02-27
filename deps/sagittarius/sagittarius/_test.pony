use "pony_test"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

fun tag tests(test: PonyTest) =>
  test(_TestDuration)
  test(_TestInstant)
  test(_TestLocalDateTime)

class iso _TestDuration is UnitTest
  fun name(): String => "duration"

  fun apply(h: TestHelper) =>
    h.assert_eq[I64](400, Duration.from_millis(400).to_millis())
    h.assert_eq[I64](300, Duration.from_millis(300).to_millis())
    h.assert_eq[I64](-100, Duration.from_millis(-100).to_millis())

    // sum of two Durations
    let sum = Duration.from_millis(400) + Duration.from_millis(300)
    h.assert_eq[I64](700, sum.to_millis())

    // positive difference
    let diff = Duration.from_millis(400) - Duration.from_millis(300)
    h.assert_eq[I64](100, diff.to_millis())

    // negative difference
    let negative_diff = Duration.from_millis(300) - Duration.from_millis(400)
    h.assert_eq[I64](-100, negative_diff.to_millis())

class iso _TestInstant is UnitTest
  fun name(): String => "instant"

  fun apply(h: TestHelper) =>
    h.assert_eq[I64](MillisPerSecond().i64(), Instant(1, 0).to_millis())
    h.assert_eq[I64](MillisPerSecond().i64() * 10, Instant(10, 0).to_millis())
    h.assert_eq[I64](1, Instant(0, NanosPerMilli().u32()).to_millis())

    // positive value
    h.assert_eq[I64](400, Instant.from_millis(400).to_millis())
    // negative value
    h.assert_eq[I64](-100, Instant.from_millis(-100).to_millis())

    // sum of Instance and Duration
    let sum = Instant.from_millis(400) + Duration.from_millis(300)
    h.assert_eq[I64](700, sum.to_millis())

    // positive difference
    let diff = Instant.from_millis(400) - Duration.from_millis(300)
    h.assert_eq[I64](100, diff.to_millis())

    // negative difference
    let negative_diff = Instant.from_millis(300) - Duration.from_millis(400)
    h.log(negative_diff.get_seconds().string())
    h.log(negative_diff.get_nanos().string())
    h.assert_eq[I64](-100, negative_diff.to_millis())


class iso _TestLocalDateTime is UnitTest
  fun name(): String => "local_date_time"

  fun apply(h: TestHelper) =>
    // 2012-02-28T00:00:00
    // 2012-02-29T00:00:00

    // 1970-01-01T00:00:00
    let zero_millis = LocalDateTime.from_millis(0)
    h.assert_eq[I32](1970, zero_millis.get_years())
    h.assert_eq[I32](1, zero_millis.get_months())
    h.assert_eq[I32](1, zero_millis.get_days())
    h.assert_eq[I32](0, zero_millis.get_hours())
    h.assert_eq[I32](0, zero_millis.get_minutes())
    h.assert_eq[I32](0, zero_millis.get_seconds())
    h.assert_eq[I32](0, zero_millis.get_nanos())
    h.assert_eq[String]("1970-01-01T00:00:00.000", zero_millis.string())

    h.assert_eq[String](
      "1970-01-01T00:00:00.001",
      LocalDateTime.from_millis(1).string())
    h.assert_eq[String](
      "1970-01-01T00:00:00.100",
      LocalDateTime.from_millis(100).string())
    h.assert_eq[String](
      "1970-01-01T00:00:01.000",
      LocalDateTime.from_millis(MillisPerSecond().i64()).string())
    h.assert_eq[String](
      "1970-01-01T00:01:00.000",
      LocalDateTime.from_millis(MillisPerMinute().i64()).string())
    h.assert_eq[String](
      "1970-01-01T01:00:00.000",
      LocalDateTime.from_millis(MillisPerHour().i64()).string())
    h.assert_eq[String](
      "1970-01-01T01:01:01.101",
      LocalDateTime
        .from_millis(
          MillisPerHour().i64() +
          MillisPerMinute().i64() +
          MillisPerSecond().i64() +
          100 +
          1)
        .string()
      )

    h.assert_eq[String](
      "1970-01-02T00:00:00.000",
      LocalDateTime.from_epoch_seconds(SecondsPerDay().i64()).string()
    )
    h.assert_eq[String](
      "1970-01-03T00:00:00.000",
      LocalDateTime.from_epoch_seconds(SecondsPerDay().i64() * 2).string()
    )
    h.assert_eq[String](
      "1971-01-01T00:00:00.000",
      LocalDateTime.from_epoch_seconds(SecondsPerDay().i64() * 365).string()
    )
    h.assert_eq[String](
      "1969-01-01T00:00:00.000",
      LocalDateTime.from_epoch_seconds(SecondsPerDay().i64() * -365).string()
    )
    h.assert_eq[String](
      "2018-01-05T10:47:15.000",
      LocalDateTime.from_epoch_seconds(1515149235).string()
    )
