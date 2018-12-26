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

        if params.season_width != 0 then
            // Ignore leapyear differences -- assume 366 days in a year
            // Radius = 91.5 days = length of season
            // Value is number of days since beginning of year (0 - 355)

            let sep = ScalarEncoderParams(
                params.season_width,
                0,
                366
            where
                name' = "Season",
                periodic' = true,
                radius' = params.season_radius
            )

            let season_encoder' = ScalarEncoder(sep) ?
            season_encoder = season_encoder'
            season_offset = width'
            width' = width' + season_encoder'.n
        else
            season_offset = 0
            season_encoder = NoOpScalarEncoder
        end


        if params.day_of_week_width != 0 then
            // Value is day of week (floating point)
            // Radius is 1 day

            let sep = ScalarEncoderParams(
                params.day_of_week_width,
                0,
                7
            where
                name' = "day of week",
                radius' = params.day_of_week_radius,
                periodic' = true
            )

            let day_of_week_encoder' = ScalarEncoder(sep) ?
            day_of_week_encoder = day_of_week_encoder'
            day_of_week_offset = width'
            width' = width' + day_of_week_encoder'.n
        else
            day_of_week_offset = 0
            day_of_week_encoder = NoOpScalarEncoder
        end

        if params.weekend_width != 0 then
            // Binary value. Not sure if this makes sense. Also is somewhat redundant
            // with dayOfWeek
            //Append radius if it was not provided

            let sep = ScalarEncoderParams(
                params.weekend_width,
                0,
                1
            where
                name' = "weekend",
                radius' = params.weekend_radius,
                periodic' = false
            )

            let weekend_encoder' = ScalarEncoder(sep) ?
            weekend_encoder = weekend_encoder'
            weekend_offset = width'
            width' = width' + weekend_encoder'.n
        else
            weekend_offset = 0
            weekend_encoder = NoOpScalarEncoder
        end

        if params.holiday_width != 0 then
            // A "continuous" binary value. = 1 on the holiday itself and smooth ramp
            // 0->1 on the day before the holiday and 1->0 on the day after the holiday.

            let sep = ScalarEncoderParams(
                params.holiday_width,
                0,
                1
            where
                name' = "holiday",
                radius' = params.holiday_radius,
                periodic' = false
            )

            let holiday_encoder' = ScalarEncoder(sep) ?
            holiday_encoder = holiday_encoder'
            holiday_offset = width'
            width' = width' + holiday_encoder'.n
        else
            holiday_offset = 0
            holiday_encoder = NoOpScalarEncoder
        end

        if params.time_of_day_width != 0 then
            // Value is time of day in hours
            // Radius = 4 hours, e.g. morning, afternoon, evening, early night,
            // late night, etc.

            let sep = ScalarEncoderParams(
                params.time_of_day_width,
                0,
                24
            where
                name' = "time of day",
                radius' = params.time_of_day_radius,
                periodic' = true
            )

            let time_of_day_encoder' = ScalarEncoder(sep) ?
            time_of_day_encoder = time_of_day_encoder'
            time_of_day_offset = width'
            width' = width' + time_of_day_encoder'.n
        else
            time_of_day_offset = 0
            time_of_day_encoder = NoOpScalarEncoder
        end

        // finally, set the total width
        width = width'



    fun encode(input: PosixDate, learn_unused: Bool = false) : Array[Bool] ? =>
        """
        Returns encoded input
        """
        var output = Array[Bool].init(false, width)

        // Get a scalar value for each subfield and encode it with the
        // appropriate encoder
        // note: a no-op encoder leaves bits as they were (false)
        season_encoder.encode_at_pos(_get_season_scalar(input), learn_unused, output, season_offset) ?

        //...

        output

    fun _get_season_scalar(date: PosixDate): F64 =>
        // todo: refactor no-op vs. ScalarEncoder behavior into a class
        //       to avoid duplicating the conditional
        if season_encoder.noop() then
            return 0.0
        end

        //make year 0 based
        (date.day_of_year - 1).f64()

    fun _get_holiday_scalar(date: PosixDate): F64 ? =>
        if holiday_encoder.noop() then
            return 0.0
        end

        // A "continuous" binary value. = 1 on the holiday itself and smooth ramp
        // 0->1 on the day before the holiday and 1->0 on the day after the holiday.
        // Currently the only holiday we know about is December 25
        // holidays is a list of holidays that occur on a fixed date every year
        var v: F64 = 0.0
        var i: USize = 0
        let holiday_size = params.holidays.size()

        while i < holiday_size do
            let h = params.holidays(i)?
            // hdate is midnight on the holiday
            // let hDate := time.Date(date.Year(), time.Month(h.A), h.B, 0, 0, 0, 0, time.UTC)
            // if date.After(hDate) {
            //     diff := date.Sub(hDate)
            //     if (diff/time.Hour)/24 == 0 {
            //         val = 1
            //         break
            //     } else if (diff/time.Hour)/24 == 1 {
            //         // ramp smoothly from 1 -> 0 on the next day
            //         val = 1.0 - (float64(diff/time.Second) / (86400))
            //         break
            //     }
            // } else {
            //     diff := hDate.Sub(date)
            //     if (diff/time.Hour)/24 == 1 {
            //         // ramp smoothly from 0 -> 1 on the previous day
            //         val = 1.0 - (float64(diff/time.Second) / 86400)
            //     }

            // }
            i = i + 1
        end

        v
