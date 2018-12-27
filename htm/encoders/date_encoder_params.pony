type HolidayMonthDay is (I32,I32)

class val DateEncoderParams
	let holiday_width:    USize // A "continuous" binary value. = 1 on the holiday itself and smooth ramp
                             // 0->1 on the day before the holiday and 1->0 on the day after the holiday.
	let holiday_radius:   F64
	let season_width:     USize
	let season_radius:    F64
	let day_of_week_width:  USize
	let day_of_week_radius: F64
	let weekend_width:    USize
	let weekend_radius:   F64
	let time_of_day_width:  USize
	let time_of_day_radius: F64
	let name: String
	//list of holidays stored as {mm,dd}
	let holidays: Array[HolidayMonthDay] val

    new val create(
        holiday_width':    USize = 0,
        holiday_radius':   F64 = 1,
        season_width':     USize = 3,
        season_radius':    F64 = 91.5, //days
        day_of_week_width':  USize = 1,
        day_of_week_radius': F64 = 1,
        weekend_width':    USize = 3,
        weekend_radius':   F64 = 1,
        time_of_day_width':  USize = 5,
        time_of_day_radius': F64 = 4,
        name': String = "DateEncoder: unknown",
        holidays': Array[HolidayMonthDay] val = []
    ) =>
        holiday_width = holiday_width'
        holiday_radius = holiday_radius'
        season_width = season_width'
        season_radius = season_radius'
        day_of_week_width = day_of_week_width'
        day_of_week_radius = day_of_week_radius'
        weekend_width = weekend_width'
        weekend_radius = weekend_radius'
        time_of_day_width = time_of_day_width'
        time_of_day_radius = time_of_day_radius'
        name = name'
        holidays = holidays'
