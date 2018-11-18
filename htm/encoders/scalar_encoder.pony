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
    // let top_down_mapping: SparseBinaryMatrix
    // let top_down_values: Array[F64]
    // let bucket_values: Array[F64]

    // calculated values
    let resolution: F64
    let n: USize
    let radius: F64
    let range: F64
	let n_internal: USize // represents the output area excluding the possible padding on each
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
