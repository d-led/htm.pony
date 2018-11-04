// https://github.com/htm-community/htm/blob/master/denseBinaryMatrix.go

primitive SetOk
primitive SetFailed
type MatrixResult is (SetOk | SetFailed)

/*
    current error handling: try setting or getting values and exit on error
    (no transactionality)
*/

class DenseBinaryMatrix
    let width: USize
    let height: USize
    let entries: Array[Bool]

    new create(width': USize, height': USize) =>
        width = width'
        height = height'
        entries = Array[Bool].init(false, width*height)

    new from_dense_2d_array(array_of_rows: Array[Array[Bool]]) ? =>
        if array_of_rows.size() == 0 then
            error
        end

        height = array_of_rows.size()
        width = array_of_rows(0)?.size()
        entries = Array[Bool].init(false, width*height)

        var r: USize = 0
        while r < height do
            if set_row_from_dense(r, array_of_rows(r)?) is SetFailed then
                error
            end

            r = r + 1
        end

    fun ref set(row: USize, col: USize, value: Bool) : MatrixResult =>
        try 
            entries((row * width) + col) ? = value
            SetOk
        else
            SetFailed
        end

    fun get(row: USize, col: USize) : Bool =>
        try
            entries((row * width) + col) ?
        else
            false
        end
    
    // Replaces specified row with values
    fun ref replace_row(row: USize, values: Array[Bool]) : MatrixResult =>
        if (values.size() != width) then
            return SetFailed
        end

        try
            var col: USize = 0
            
            while col < width do
                // should not return an error, as per range check above
                set(row, col, values(col) ?)
                col = col + 1
            end

            SetOk
        else
            SetFailed
        end

    // Replaces row with true values at specified indices
    fun ref replace_row_by_indices(row: USize, indices: Array[USize]) : MatrixResult =>
        try
            let start = row * width
            var i: USize = 0
            while i < width do
                entries(start + i) ? = indices.contains(i)
                i = i + 1
            end

            SetOk
        else
            SetFailed
        end

    fun get_row_indices(row: USize) : Array[USize] =>
        var result = Array[USize]
        result.reserve(width) // <- this might be unnecessary (try benchmark)
        let start = row * width
        var i: USize = 0
        while i < width do
            try
                if entries(start + i)? then
                    result.push(i)
                end
            end

            i = i + 1
        end

        result

    // Replaces row with true values at specified indices
    fun ref set_row_from_dense(row: USize, row_values: Array[Bool]) : MatrixResult =>
        try
            let start = row * width
            var i: USize = 0
            while i < width do
                entries(start + i) ? = row_values(i) ?
                i = i + 1
            end

            SetOk
        else
            SetFailed
        end

    fun _split_index(index: USize) : (USize, USize) =>
        let row = index / width
        let col = index % width
	    (row, col)

    // looks like a matrix product with a vector + sum of the true entries
    // needs a better name, perhaps
    fun row_and_sum(row_to_sum: Array[Bool]) : Array[USize] =>
        var result = Array[USize].init(0, height)

        try
            var i: USize = 0
            let size = entries.size()

            while i < size do
                if entries(i) ? then
                    (var row, var col) = _split_index(i)
                    if row_to_sum(col)? then
                        result(row)? = result(row)? + 1
                    end
                end
                
                i = i + 1
            end
        end

        result
