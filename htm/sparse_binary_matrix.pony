use "collections"
use "debug"

// entries are positions of non-zero values
class val SparseEntry
    let row: USize
    let col: USize

    new val create(row': USize, col': USize) =>
        row = row'
        col = col'

// some methods are duplicated from dense matrix
class SparseBinaryMatrix
    let width: USize
    let height: USize
    let entries: Array[SparseEntry]

    new create(width': USize, height': USize) =>
        width = width'
        height = height'
        entries = Array[SparseEntry]

    new from_dense_2d_array(array_of_rows: Array[Array[Bool]]) ? =>
        if array_of_rows.size() == 0 then
            Debug.err("SparseBinaryMatrix.from_dense_2d_array: empty input")
            error
        end

        height = array_of_rows.size()
        width = array_of_rows(0)?.size()
        entries = Array[SparseEntry]

        var r: USize = 0
        while r < height do
            if set_row_from_dense(r, array_of_rows(r)?) is SetFailed then
                Debug.err("SparseBinaryMatrix.from_dense_2d_array: set_row_from_dense failed")
                error
            end

            r = r + 1
        end


    fun ref set(row: USize, col: USize, value: Bool) : MatrixResult =>
        if (row > (height - 1)) or (col > (width - 1)) then
            Debug.err("SparseBinaryMatrix.set: wrong row/col: " + row.string() + "/" + col.string())
            return SetFailed
        end

        if not value then
            return _delete(row, col)
        end

        if get(row, col) then
            return SetOk
        end
        
        entries.push(SparseEntry(row, col))

        SetOk


    fun get(row: USize, col: USize) : Bool =>
        try
            _lookup(row, col) ?
            true
        else
            false
        end

    // Replaces specified row with values
    fun ref replace_row(row: USize, values: Array[Bool]) : MatrixResult =>
        if (values.size() != width) then
            Debug.err("SparseBinaryMatrix.replace_row: widths mismatch values/width: " + values.size().string() + "/" + width.string())
            return SetFailed
        end
        
        try
            var col: USize = 0
            
            while col < width do
                // should not return an error, as per range check above. todo: check
                set(row, col, values(col) ?)
                col = col + 1
            end

            SetOk
        else
            Debug.err("SparseBinaryMatrix.replace_row returned: SetFailed")
            SetFailed
        end

    // Replaces row with true values at specified indices
    fun ref replace_row_by_indices(row: USize, indices: Array[USize]) : MatrixResult =>
        if row > (height - 1) then
            Debug.err("SparseBinaryMatrix.replace_row_by_indices: wrong row index: row/height: " + row.string() + "/" + height.string())
            return SetFailed
        end

        try
            var i: USize = 0
            while i < width do
                var value: Bool = false
                var x: USize = 0
                let size = indices.size()
                while x < size do
                    if i == indices(x)? then
                        value = true
                        break
                    end
                    x = x + 1
                end
                set(row, i, value) // todo: check
                i = i + 1
            end

            SetOk
        else
            Debug.err("SparseBinaryMatrix.replace_row_by_indices returned: SetFailed")
            SetFailed
        end

    // empty array returned might indicate a range error
    fun get_row_indices(row: USize) : Array[USize] =>
        var result = Array[USize](width)
        
        if row > (height - 1) then
            Debug.err("SparseBinaryMatrix.get_row_indices: wrong row index: row/height: " + row.string() + "/" + height.string())
            return result
        end

        let size = entries.size()
        var i: USize = 0
        while i < size do
            try
                if entries(i)?.row == row then
                    result.push(entries(i)?.col)
                end
            end

            i = i + 1
        end

        result

    // Replaces row with true values at specified indices
    fun ref set_row_from_dense(row: USize, row_values: Array[Bool]) : MatrixResult =>
        if row > (height - 1) then
            Debug.err("SparseBinaryMatrix.set_row_from_dense: wrong row index: row/height: " + row.string() + "/" + height.string())
            return SetFailed
        end

        try
            var i: USize = 0
            while i < width do
                set(row, i, row_values(i)?) // todo: check
                i = i + 1
            end

            SetOk
        else
            SetFailed
        end

    fun row_and_sum(row_to_sum: Array[Bool]) : Array[USize] =>
        var result = Array[USize].init(0, height)

        if row_to_sum.size() > (width - 1) then
            Debug.err("SparseBinaryMatrix.row_and_sum: width mismatch: row_to_sum/width: " + row_to_sum.size().string() + "/" + width.string())
            return result            
        end

        try
            var i: USize = 0
            let size = entries.size()

            while i < size do
                let entry = entries(i)?
                if row_to_sum(entry.col) ? then
                    result(entry.row)? = result(entry.row)? + 1
                end
                
                i = i + 1
            end
        end

        result


    fun _lookup(row: USize, col: USize) : USize ? =>
        // somewhat contrived. find returns an error if nothing is found
        entries.find(SparseEntry(row,col) where predicate = {
            (l: SparseEntry, r: SparseEntry): Bool => (l.row == r.row) and (l.col == r.col)
        }) ?

    fun ref _delete(row: USize, col: USize) : MatrixResult =>
        try
            let pos = _lookup(row, col) ?
            entries.remove(pos,1)
            SetOk
        else
            // Debug.err("SparseBinaryMatrix._delete returned: SetFailed")
            SetFailed
        end
