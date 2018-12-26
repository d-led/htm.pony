/*
	Date encoder encodes a datetime to a SDR. Params allow for tuning
	for specific date attributes
*/
class DateEncoder
    let params: DateEncoderParams
	let season_encoder:      (ScalarEncoder | None)
	let day_of_week_encoder: (ScalarEncoder | None)
	// let holiday_encoder:     (ScalarEncoder | None)
	// let weekend_encoder:     (ScalarEncoder | None)
	// let time_of_day_encoder: (ScalarEncoder | None)

	let width:              USize
	let season_offset:      USize
	let day_of_week_offset: USize
    // let weekend_offset:     USize
	// let holiday_offset:     USize
	// let time_of_day_offset: USize

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
            season_encoder = None
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
            day_of_week_encoder = None
        end

        // finally, set the total width
        width = width'
