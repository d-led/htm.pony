// https://github.com/htm-community/htm/blob/master/denseBinaryMatrix.go

primitive SetOk
primitive SetFailed
type MatrixResult is (SetOk | SetFailed)

class DenseBinaryMatrix
    let width: USize
    let height: USize
    let entries: Array[Bool]

    new create(width': USize, height': USize) =>
        width = width'
        height = height'
        entries = Array[Bool].init(false, width*height)

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
