// Ported from encoders/dateEncoder.go in htm-community/htm (MIT).
// See docs/sources.md.
use "time"

class DateEncoder
    """
    Date encoder encodes a datetime to a SDR. Params allow for tuning
	for specific date attributes
    """

    let params: DateEncoderParams
	var season_encoder:      SomeScalarEncoder
	let day_of_week_encoder: SomeScalarEncoder
	let weekend_encoder:     SomeScalarEncoder
    let holiday_encoder:     SomeScalarEncoder
	let time_of_day_encoder: SomeScalarEncoder

	let width:              USize
	let season_offset:      USize
	let day_of_week_offset: USize
    let weekend_offset:     USize
	let holiday_offset:     USize
	let time_of_day_offset: USize

    new create(params': DateEncoderParams val) ? =>
        params = params'

        var width': USize = 0

        let season = DateField.build(
          params.season_width,
          366,
          "Season",
          params.season_radius,
          true,
          width')?
        season_encoder = season._1
        season_offset = season._2
        width' = width' + season._3


        let day = DateField.build(
          params.day_of_week_width,
          7,
          "day of week",
          params.day_of_week_radius,
          true,
          width')?
        day_of_week_encoder = day._1
        day_of_week_offset = day._2
        width' = width' + day._3

        let weekend = DateField.build(
          params.weekend_width,
          1,
          "weekend",
          params.weekend_radius,
          false,
          width')?
        weekend_encoder = weekend._1
        weekend_offset = weekend._2
        width' = width' + weekend._3

        let holiday = DateField.build(
          params.holiday_width,
          1,
          "holiday",
          params.holiday_radius,
          false,
          width')?
        holiday_encoder = holiday._1
        holiday_offset = holiday._2
        width' = width' + holiday._3

        let time_of_day = DateField.build(
          params.time_of_day_width,
          24,
          "time of day",
          params.time_of_day_radius,
          true,
          width')?
        time_of_day_encoder = time_of_day._1
        time_of_day_offset = time_of_day._2
        width' = width' + time_of_day._3

        // finally, set the total width
        width = width'



    fun encode(input: PosixDate, learn_unused: Bool = false) : (Array[Bool] | EncodingFailed) =>
        """
        Returns encoded input
        """
        let output = Array[Bool].init(false, width)

        // Get a scalar value for each subfield and encode it with the
        // appropriate encoder. A field nobody asked for is a no-op encoder,
        // which writes nothing and cannot fail, so its slice stays clear.

        match season_encoder.encode_at_pos(
            _get_season_scalar(input), learn_unused, output, season_offset)
        | EncodingFailed => return EncodingFailed
        end

        match day_of_week_encoder.encode_at_pos(
            _get_day_of_week_scalar(input), learn_unused, output, day_of_week_offset)
        | EncodingFailed => return EncodingFailed
        end

        match weekend_encoder.encode_at_pos(
            _get_weekend_scalar(input), learn_unused, output, weekend_offset)
        | EncodingFailed => return EncodingFailed
        end

        match holiday_encoder.encode_at_pos(
            _get_holiday_scalar(input), learn_unused, output, holiday_offset)
        | EncodingFailed => return EncodingFailed
        end

        match time_of_day_encoder.encode_at_pos(
            _get_time_of_day_scalar(input), learn_unused, output, time_of_day_offset)
        | EncodingFailed => return EncodingFailed
        end

        output

    fun _get_season_scalar(date: PosixDate): F64 =>
        // the encoder's range is the days of a year, and a leap year is assumed
        // to have 366 of them
        (date.day_of_year - 1).f64()

    fun _get_day_of_week_scalar(date: PosixDate): F64 =>
        _weekday(date).f64()

    fun _get_weekend_scalar(date: PosixDate): F64 =>
        let weekday = _weekday(date)
        if (weekday == 0) or (weekday == 6) then 1.0 else 0.0 end

    fun _get_time_of_day_scalar(date: PosixDate): F64 =>
        // hours, with the minutes and seconds as fractions of one
        date.hour.f64() + (date.min.f64() / 60.0) + (date.sec.f64() / 3600.0)

    fun _get_holiday_scalar(date: PosixDate): F64 =>
        """
        One on the holiday itself, rising from nothing over the day before it
        and falling back over the day after - the shape the reference describes.

        A holiday is a month and a day, so it is looked up in the date's own
        year; a date near New Year is therefore next to the same year's holiday
        rather than the neighbouring year's.
        """
        let today = _days(date.year, date.month, date.day_of_month)
        let seconds: F64 =
            (date.hour * 3600).f64() + (date.min * 60).f64() + date.sec.f64()

        for holiday in params.holidays.values() do
            (let month, let day) = holiday
            let apart = today - _days(date.year, month, day)

            if apart == 0 then
                return 1.0
            elseif apart == 1 then
                // the day after: full at midnight, gone by the next one
                return 1.0 - (seconds / 86400.0)
            elseif apart == -1 then
                // the day before: nothing at midnight, full at the next
                return seconds / 86400.0
            end
        end

        0.0

    fun _weekday(date: PosixDate): USize =>
        """
        Sunday is 0, which is the order the day-of-week encoder is given. The
        fourth of January 1970 was a Sunday, so the epoch's Thursday is four.
        """
        let days = _days(date.year, date.month, date.day_of_month) + 4
        (((days % 7) + 7) % 7).usize()

    fun _days(year: I32, month: I32, day: I32): I64 =>
        """
        Days from 1970-01-01 to this calendar day: days-from-civil, which is
        exact for every date a `PosixDate` can hold and needs no table.
        """
        let shifted: I64 = if month <= 2 then year.i64() - 1 else year.i64() end
        let era =
            (if shifted >= 0 then shifted else shifted - 399 end) / 400
        let year_of_era = shifted - (era * 400)
        let month_of_year: I64 = month.i64()
        let day_of_year =
            ((((153 * (month_of_year + (if month_of_year > 2 then -3 else 9 end))) + 2) / 5)
                + day.i64()) - 1
        let day_of_era =
            (((year_of_era * 365) + (year_of_era / 4)) - (year_of_era / 100)) + day_of_year
        ((era * 146097) + day_of_era) - 719468
