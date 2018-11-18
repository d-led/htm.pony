// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder.go

use "../../htm"
use "debug"

// comment taken verbatim from the original
/*
 A scalar encoder encodes a numeric (floating point) value into an array
of bits. The output is 0's except for a contiguous block of 1's. The
location of this contiguous block varies continuously with the input value.
The encoding is linear. If you want a nonlinear encoding, just transform
the scalar (e.g. by applying a logarithm function) before encoding.
It is not recommended to bin the data as a pre-processing step, e.g.
"1" = $0 - $.20, "2" = $.21-$0.80, "3" = $.81-$1.20, etc. as this
removes a lot of information and prevents nearby values from overlapping
in the output. Instead, use a continuous transformation that scales
the data (a piecewise transformation is fine).
*/

class ScalarEncoder
    let params: ScalarEncoderParams

    var padding: USize = 0
    let half_width: USize
    let range_internal: F64
    
    var top_down_mapping: (SparseBinaryMatrix | None) = None
    var top_down_values: Array[F64] = []
    var bucket_values: Array[F64] = []

    // calculated values
    let resolution: F64
    let n: USize
    let radius: F64
    let range: F64
	let n_internal: USize // represents the output area excluding the possible padding on each side
    let name: String

    new create(params': ScalarEncoderParams val) ? =>
        params = params'

        if (params.width % 2) == 0 then
		    Debug.err("ScalarEncoder: width must be an odd number. Input: " + params.width.string())
            error
	    end

        half_width = (params.width - 1) / 2

        /*  For non-periodic inputs, padding is the number of bits "outside" the range,
            on each side. I.e. the representation of minval is centered on some bit, and
            there are "padding" bits to the left of that centered bit; similarly with
            bits to the right of the center bit of maxval
        */
        
        if  not params.periodic then
            padding = half_width
        end

        if params.min_val >= params.max_val then
            Debug.err("ScalarEncoder: min_val must be less than max_val: " + params.min_val.string() + " >= " + params.max_val.string())
            error
        end

        range_internal = params.max_val - params.min_val

        // There are three different ways of thinking about the representation. Handle
        // each case here.
        // inline initEncoder. TODO: consider a pony-conforming refactoring strategy


        if params.n != 0 then
            //crutches ;(
            if params.radius != 0 then
             	Debug.err("ScalarEncoder: input radius is not 0")
                error
            end

            if params.resolution != 0 then
            	Debug.err("ScalarEncoder: resolution is not 0")
                error
            end

            if params.n <= params.width then
            	Debug.err("ScalarEncoder: n less than width: " + params.n.string() + "/" + params.width.string())
                error
            end

            n = params.n

            if not params.periodic then
            	resolution = range_internal / (params.n.f64() - params.width.f64())
            else
            	resolution = range_internal / params.n.f64()
            end

            radius = params.width.f64() * resolution

            if params.periodic then
            	range = range_internal
            else
            	range = range_internal + resolution
            end
        else //n == 0
            true
            if params.radius != 0 then
            	if params.resolution != 0 then
            		Debug.err("ScalarEncoder: resolution not 0")
                    error
            	end
                radius = params.radius
                resolution = params.radius / params.width.f64()
            elseif params.resolution != 0 then
                resolution = params.resolution
            	radius = params.resolution * params.width.f64()
            else
            	Debug.err("ScalarEncoder: One of n, radius, resolution must be set")
                error
            end

            if params.periodic then
            	range = range_internal
            else
            	range = range_internal + resolution
            end

            let nfloat = (params.width.f64() * (range/radius)) + (2 * padding.f64())
            n = nfloat.ceil().usize()
        end

        n_internal = n - (2 * padding)

        if params.name.size() == 0 then
        	name = "[" + params.min_val.string() + ":" + params.max_val.string() + "]"
        else 
            name = params.name
        end

        if params.width < 21 then
        	Debug.out("WARNING: ScalarEncoder: Number of bits in the SDR must be greater than 21. Now: " + params.width.string())
            // error // not an error in the original
        end

    /*
        Returns encoded input
    */
    fun encode(input: F64, learn_unused: Bool) : Array[Bool] ? =>
        var output = Array[Bool].init(false, n)
        
        // The bucket index is the index of the first bit to set in the output
        let bucketIdx = _get_first_on_bit(input)?
        
        var minbin = bucketIdx
        var maxbin = minbin + (2 * half_width.i64())
        var bottombins: I64 = 0
        var topbins: I64 = 0

        if params.periodic then

            // Handle the edges by computing wrap-around
            if maxbin >= n.i64() then
                bottombins = (maxbin - n.i64()) + 1
                try 
                    _fill_slice_range_bool(output , true, 0, bottombins.usize())?
                else
                    Debug.err("ScalarEncoder.encode[1] failed")
                    error
                end
                maxbin = n.i64() - 1
            end
           
            if minbin < 0 then
                topbins = -minbin
                try 
                    _fill_slice_range_bool(output, true, n-topbins.usize(), (n - (n - topbins.usize())).usize())?
                else
                    Debug.err("ScalarEncoder.encode[2] failed")
                    error
                end                
                minbin = 0
            end
        end

        if minbin < 0 then
            Debug.err("ScalarEncoder.encode: invalid minbin: " + minbin.string())
            error
        end

        if maxbin >= n.i64() then
            Debug.err("ScalarEncoder.encode: invalid maxbin: " + maxbin.string())
            error
        end


        // set the output (except for periodic wraparound)
        try 
            _fill_slice_range_bool(output, true, minbin.usize(), ((maxbin+1)-minbin).usize())?
        else
            Debug.err("ScalarEncoder.encode[3] failed")
            error
        end         

        // if se.Verbosity >= 2 {
        //     fmt.Println("input:", input)
        //     fmt.Printf("half width:%v \n", se.Width)
        //     fmt.Printf("range: %v - %v \n", se.MinVal, se.MaxVal)
        //     fmt.Printf("n: %v width: %v resolution: %v \n", se.N, se.Width, se.Resolution)
        //     fmt.Printf("radius: %v periodic: %v \n", se.Radius, se.Periodic)
        //     fmt.Printf("output: %v \n", output)
        // }

        // end

        output

    /*  Return the bit offset of the first bit to be set in the encoder output.
        For periodic encoders, this can be a negative number when the encoded output
        wraps around.
    */
    fun _get_first_on_bit(input: F64) : I64 ? =>
        var clipped_input = input
        if input < params.min_val then
            //Don't clip periodic inputs. Out-of-range input is always an error
		    if params.clip_input and (not params.periodic) then
                // 	if params.Verbosity > 0 {
                // 		fmt.Printf("Clipped input %v=%v to minval %v", params.Name, input, params.min_val)
                // 	}
                clipped_input = params.min_val
            else
        		Debug.err("ScalarEncoder._get_first_on_bit: Input "+input.string() + " less than range " + params.min_val.string() + " - " + params.max_val.string())
                error 
            end

            if params.periodic then
                // Don't clip periodic inputs. Out-of-range input is always an error
                if input >= params.max_val then
                    // panic(fmt.Sprintf("input %v greater than periodic range %v - %v", input, params.min_val, params.MaxVal))
            		Debug.err("ScalarEncoder._get_first_on_bit: Input "+input.string() + " greater than periodic range " + params.min_val.string() + " - " + params.max_val.string())
                    error
                end
            else
                if input > params.max_val then
                    if params.clip_input then
                        // if params.Verbosity > 0 {
                        //     fmt.Printf("Clipped input %v=%v to maxval %v", params.Name, input, params.MaxVal)
                        // }
                        clipped_input = params.max_val
                    else
                		Debug.err("ScalarEncoder._get_first_on_bit: Input "+input.string() + " greater than range (" + params.min_val.string() + " - " + params.max_val.string() + ")")
                        error
                    end
                end
            end
        end

        var centerbin: I64 = 0

        if params.periodic then
            centerbin = ((((input-params.min_val)*n_internal.f64())/range) + padding.f64()).i64()
        else
            centerbin = ((((input-params.min_val)+(resolution/2))/resolution) + padding.f64()).i64()
        end

        // We use the first bit to be set in the encoded output as the bucket index
        centerbin - half_width.i64()

    // Populates bool slice with specified value
    fun _fill_slice_range_bool(values: Array[Bool] ref, value: Bool, start: USize, length: USize) ? =>
        var i : USize = 0

        while i < length do
            values(start+i) ? = value
            i = i + 1
        end
