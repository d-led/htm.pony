// https://github.com/htm-community/htm/blob/master/encoders/scalerEncoder.go

use "../../htm"
use "../../htm/util"
use "debug"
use "itertools"

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

    fun noop(): Bool => false

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
        encode_at_pos(input, learn_unused, output, 0) ?
        output

    /*
        Puts encoded input inline into the output array
    */
    fun encode_at_pos(input: F64, learn_unused: Bool, output: Array[Bool] ref, pos: USize) ? =>  
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
        //     fmt.Printf("range: %v - %v \n", params.min_val, se.MaxVal)
        //     fmt.Printf("n: %v width: %v resolution: %v \n", se.N, se.Width, params.resolution)
        //     fmt.Printf("radius: %v periodic: %v \n", se.Radius, params.periodic)
        //     fmt.Printf("output: %v \n", output)
        // }

        // end

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
    
    // Decode an encoded sequence. Returns range of values
    fun decode(encoded: Array[Bool]): Array[ScalarRange] ? =>
        if not encoded.contains(true) then
            return []
        end

	    var tmpOutput = encoded.slice(0, this.n)

        // First, assume the input pool is not sampled 100%, and fill in the
        // "holes" in the encoded representation (which are likely to be present
        // if this is a coincidence that was learned by the SP).

        // 	// Search for portions of the output that have "holes"
        let maxZerosInARow = this.half_width
        var i : USize = 0

        while i < maxZerosInARow do
            var searchSeq = Array[Bool].init(false, i+3)
     		let subLen = searchSeq.size()
    		searchSeq(0) ? = true
    		searchSeq(subLen-1) ? = true

    		if params.periodic then
                var j : USize = 0
        		while j < this.n do
                    var outputIndices = Array[USize].init(0, subLen)

                    var idx : USize = 0
                    while idx < subLen do
                        outputIndices (idx) ? = (j + idx) % this.n
                        idx = idx + 1
                    end

                    let subset = BoolArray.subset_slice(tmpOutput, outputIndices) ?

                    if BoolArray.are_equal(
                        searchSeq,
                        subset
                    ) then
                        BoolArray.set_value_at_indices(tmpOutput, outputIndices, true) ?
                    end

                    j = j + 1
    			end

    		else
                var j: USize = 0
                while j < ((this.n - subLen) + 1) do
                    if BoolArray.are_equal(
                        searchSeq,
                        tmpOutput.slice(j, j + subLen)
                    ) then
					    BoolArray.set_value_in_range(tmpOutput, true, j, subLen) ?
                    end
                end
    		end

            i = i + 1
        end

        // 	if se.Verbosity >= 2 {
        // 		fmt.Println("raw output:", utils.Bool2Int(encoded[:se.N]))
        // 		fmt.Println("filtered output:", utils.Bool2Int(tmpOutput))
        // 	}

        // ------------------------------------------------------------------------
        // Find each run of 1's in sequence

        let nz = BoolArray.on_indices(tmpOutput)
        //key = start index, value = run length
        var runs = Array[(USize,USize)](nz.size())
        var runStart: (None | USize) = None // None to indicate -1 in the original
        var runLen: USize = 0
        var idx: USize = 0
        let tmpOutputSize = tmpOutput.size()

        while idx < tmpOutputSize do
            var value = tmpOutput(idx) ?
        		if value then
                    if runStart is None then
                        runStart = idx
        				runLen = 0
                    end 
        			runLen = runLen + 1
        		else
                    true
                    if not (runStart is None) then
        				runs.push((runStart as USize, runLen))
        				runStart = None
        			end
        		end
            idx = idx + 1
        end

        if not (runStart is None) then
        		runs.push((runStart as USize, runLen))
        		runStart = None
        end

        // If we have a periodic encoder, merge the first and last run if they
        // both go all the way to the edges
        if params.periodic and (runs.size() > 1) then
            if (runs(0)?._1 == 0) and ((runs(runs.size()-1)?._1 + runs(runs.size()-1)?._2) == this.n) then
                runs(runs.size()-1)? = (runs(runs.size()-1)?._1, runs(runs.size()-1)?._2 + runs(0)?._2)
                runs = runs.slice(1)
            end
        end

        // ------------------------------------------------------------------------
        // Now, for each group of 1's, determine the "left" and "right" edges, where
        // the "left" edge is inset by halfwidth and the "right" edge is inset by
        // halfwidth.
        // For a group of width w or less, the "left" and "right" edge are both at
        // the center position of the group.

        var	ranges = Array[ScalarRange](runs.size()+2)
        let runsSize = runs.size()
        var run: USize = 0
        while run < runsSize do
            let value = runs(run) ?
            var left: USize = 0
            var right: USize = 0
    		let start = value._1
    		let length = value._2

    		if length <= params.width then
    			right = start + (length/2)
    			left = right
            else
    			left = start + this.half_width
    			right = ((start + length) - 1) - this.half_width
    		end

    		var inMin: F64 = 0
            var inMax: F64 = 0

    		// Convert to input space.
    		if not params.periodic then
    			inMin = ((left-this.padding).f64()*params.resolution) + params.min_val
    			inMax = ((right-this.padding).f64()*params.resolution) + params.min_val
    		else
    			inMin = (((left-this.padding).f64()*this.range)/(this.n_internal.f64())) + params.min_val
    			inMax = (((right-this.padding).f64()*this.range)/(this.n_internal.f64())) + params.min_val
    		end

    		// Handle wrap-around if periodic
    		if params.periodic then
    			if inMin >= params.max_val then
    				inMin = inMin - this.range
    				inMax = inMax - this.range
    			end
    		end

    		// Clip low end
    		if inMin < params.min_val then
    			inMin = params.min_val
    		end
    		if inMax < params.min_val then
    			inMax = params.min_val
    		end

    		// If we have a periodic encoder, and the max is past the edge, break into
    		// 2 separate ranges

    		if params.periodic and (inMax >= params.max_val) then
    			ranges.push(ScalarRange(inMin, params.max_val))
    			ranges.push(ScalarRange(params.min_val, inMax - this.range))
    		else 
    			//clip high end
    			if inMax > params.max_val then
    				inMax = params.max_val
    			end
    			if inMin > params.max_val then
    				inMin = params.max_val
    			end
    			ranges.push(ScalarRange(inMin, inMax))
    		end
            run = run + 1
        end

        //desc := se.generateRangeDescription(ranges)

        ranges
