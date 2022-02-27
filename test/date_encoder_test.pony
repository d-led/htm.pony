use "pony_test"
use "../htm/encoders"
use "../htm/util"
// use "debug"
use "time"

// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder_test.go

class DateEncodingTest is TestList
  fun name(): String => "Date encoder"
  
  fun tag tests(test: PonyTest) =>
    test(_TestSimpleDateEncoding)

class iso _TestSimpleDateEncoding is UnitTest
  fun name(): String => "Simple date encoder basics"

  fun apply(h: TestHelper) ? =>
    let p = DateEncoderParams(where
      season_width' = 3,
      day_of_week_width' = 1,
      weekend_width' = 3,
      time_of_day_width' = 5
    )
    let de = DateEncoder(p) ?
  
    // season is aaabbbcccddd (1 bit/month)  TODO should be <<3?
    // should be 000000000111 (centered on month 11 - Nov)
    let seasonExpected = BoolArray.from01([0;0;0;0;0;0;0;0;0;1;1;1])
    // week is SMTWTFS
    // differs from python implementation
    let dayOfWeekExpected = BoolArray.from01([0;0;0;0;1;0;0])
    // not a weekend, so it should be "False"
    let weekendExpected = BoolArray.from01([1;1;1;0;0;0])
    // time of day has radius of 4 hours and w of 5 so each bit = 240/5 min = 48min
    // 14:55 is minute 14*60 + 55 = 895; 895/48 = bit 18.6
    // should be 30 bits total (30 * 48 minutes = 24 hours)
    let timeOfDayExpected = BoolArray.from01([0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;1;1;1;1;0;0;0;0;0;0;0;0;0])

    // original: time.Date(2010, 11, 4, 14, 55, 0, 0, time.UTC) --> .Unix() == 1288882500
    let d = PosixDate(1288882500/*seconds*/,/*nanoseconds*/0)
    h.assert_eq[I32](2010, d.year)
    h.assert_eq[I32](11, d.month)
    h.assert_eq[I32](4, d.day_of_month)
    h.assert_eq[I32](14, d.hour)
    h.assert_eq[I32](55, d.min)
    h.assert_eq[I32](0, d.sec)
    h.assert_eq[I32](0, d.nsec)

    let encoded = de.encode(d) as Array[Bool]

    h.log("t1288882500 encoded: " + (";".join(encoded.values())))
    // t.Log(utils.Bool2Int(encoded))

    // expected = append(seasonExpected, dayOfWeekExpected...)
    // expected = append(expected, weekendExpected...)
    // expected = append(expected, timeOfDayExpected...)

    // assert.Equal(t, utils.Bool2Int(expected), utils.Bool2Int(encoded))