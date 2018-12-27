primitive MillisPerSecond fun apply(): U32 => 1_000
primitive MillisPerMinute fun apply(): U32 => SecondsPerMinute().u32() * MillisPerSecond()
primitive MillisPerHour fun apply(): U32 => MillisPerMinute() * MinutesPerHour().u32()
primitive NanosPerSecond fun apply(): U32 => 1_000_000_000
primitive NanosPerMilli fun apply(): U32 => 1_000_000
primitive NanosPerMinute fun apply(): U64 => NanosPerSecond().u64() * SecondsPerMinute().u64()
primitive NanosPerHour fun apply(): U64 => NanosPerSecond().u64() * SecondsPerHour().u64()
primitive SecondsPerMinute fun apply(): U16 => 60
primitive SecondsPerHour fun apply(): U16 => SecondsPerMinute() * MinutesPerHour()
primitive MinutesPerHour fun apply(): U16 => 60
primitive HoursPerDay fun apply(): U16 => 24
primitive MinutesPerDay fun apply(): U16 => MinutesPerHour() * HoursPerDay()
primitive SecondsPerDay fun apply(): U32 => SecondsPerMinute().u32() * MinutesPerDay().u32()

/**
  * The number of days from year zero to year 1970.
  * There are five 400 year cycles from year zero to 2000.
  * There are 7 leap years from 1970 to 2000.
  */
primitive DaysSinceEpoch fun apply(): U32 => (DaysPer400YearCycle() * 5) - ((30 * 365) + 7)
primitive DaysPer400YearCycle fun apply(): U32 => 146097
