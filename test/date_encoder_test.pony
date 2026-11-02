use "pony_test"
use "../htm/encoders"
use "../htm/util"
use "time"

// The Go reference: encoders/dateEncoder_test.go, whose expectations these are.

class DateEncodingTest is TestList
  fun name(): String => "Date encoder"

  fun tag tests(test: PonyTest) =>
    test(_EveryFieldOfADateIsWritten)
    test(_OnlyADateNearAHolidayIsHoliday)

primitive DateFixture
  """
  The instant the reference uses: 2010-11-04 14:55:00 UTC, a Thursday.
  """
  fun date(): PosixDate => PosixDate(1288882500 /* seconds */, 0)

  fun params(): DateEncoderParams val =>
    DateEncoderParams(where
      season_width' = 3,
      day_of_week_width' = 1,
      weekend_width' = 3,
      time_of_day_width' = 5)

class iso _EveryFieldOfADateIsWritten is UnitTest
  fun name(): String => "every field a date asks for is written, in its own slice"

  fun apply(h: TestHelper) ? =>
    let date = DateFixture.date()

    // the fixture is what the reference's expectations were written against
    h.assert_eq[I32](2010, date.year)
    h.assert_eq[I32](11, date.month)
    h.assert_eq[I32](4, date.day_of_month)
    h.assert_eq[I32](14, date.hour)
    h.assert_eq[I32](55, date.min)

    let expected = _concatenated([
      // season: one bit a month, centred on November
      [0; 0; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1]
      // day of week, SMTWTFS: Thursday
      [0; 0; 0; 0; 1; 0; 0]
      // weekend, false
      [1; 1; 1; 0; 0; 0]
      // time of day, a bit per 48 minutes: 14:55 is bit 18 of 30
      [0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1; 1; 1; 0; 0; 0; 0; 0; 0; 0; 0; 0]
    ])

    match DateEncoder(DateFixture.params())?.encode(date)
    | let encoded: Array[Bool] =>
      h.assert_eq[USize](expected.size(), encoded.size(), "the width of the encoding")
      h.assert_true(
        BoolArray.are_equal(expected, encoded),
        "expected " + _bits(expected) + " and got " + _bits(encoded))
    | EncodingFailed => h.fail("a date this ordinary should encode")
    end

  fun _concatenated(parts: Array[Array[U8]]): Array[Bool] =>
    let all = Array[Bool]
    for part in parts.values() do
      for bit in part.values() do
        all.push(bit != 0)
      end
    end
    all

  fun _bits(values: Array[Bool]): String =>
    var text: String = ""
    for value in values.values() do
      text = text + (if value then "1" else "0" end)
    end
    text

class iso _OnlyADateNearAHolidayIsHoliday is UnitTest
  fun name(): String => "only a date on or beside a holiday is encoded as one"

  fun apply(h: TestHelper) ? =>
    // Christmas, so the days either side of it can be compared with it
    let holidays: Array[(I32, I32)] val = recover val [(12, 25)] end
    let encoder = DateEncoder(DateEncoderParams(where
      holiday_width' = 3,
      season_width' = 0,
      day_of_week_width' = 0,
      weekend_width' = 0,
      time_of_day_width' = 0,
      holidays' = holidays))?

    // the holiday is the only field asked for, so its bits are the encoding
    h.assert_eq[USize](6, encoder.width, "three bits of history, so six of encoding")

    let july = PosixDate(1593604800, 0)          // 2020-07-01 12:00
    let next_july = PosixDate(1593691200, 0)     // 2020-07-02 12:00
    let eve_start = PosixDate(1608768000, 0)     // 2020-12-24 00:00
    let eve_end = PosixDate(1608854340, 0)       // 2020-12-24 23:59
    let noon_before = PosixDate(1608811200, 0)   // 2020-12-24 12:00
    let on = PosixDate(1608897600, 0)            // 2020-12-25 12:00

    h.assert_eq[I32](7, july.month)
    h.assert_eq[I32](24, eve_start.day_of_month)
    h.assert_eq[I32](25, on.day_of_month)

    // a scalar encoder writes bits for the value it is given, so "no holiday"
    // is the bottom of its range rather than an empty slice: the pair to
    // compare is two days that are both no holiday
    h.assert_eq[String](_bits(encoder, july)?, _bits(encoder, next_july)?,
      "two ordinary days carry the same holiday value")

    h.assert_true(_bits(encoder, on)? != _bits(encoder, july)?,
      "the holiday itself is not an ordinary day")
    h.assert_true(_bits(encoder, noon_before)? != _bits(encoder, july)?,
      "the day before a holiday is already ramping towards it")
    h.assert_true(_bits(encoder, eve_start)? != _bits(encoder, eve_end)?,
      "the ramp moves through the day before it arrives")

  fun _bits(encoder: DateEncoder, date: PosixDate): String ? =>
    match encoder.encode(date)
    | let encoded: Array[Bool] =>
      var text: String = ""
      for value in encoded.values() do
        text = text + (if value then "1" else "0" end)
      end
      text
    | EncodingFailed => error
    end
