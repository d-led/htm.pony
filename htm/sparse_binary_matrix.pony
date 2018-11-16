use "collections"

// entries are positions of non-zero values
class val SparseEntry
    let row: USize
    let col: USize

    new create(row': USize, col': USize) =>
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
        entries = Array[SparseEntry]()

    fun ref set(row: USize, col: USize, value: Bool) : MatrixResult =>
        if (row > (height - 1)) or (col > (width - 1)) then
            return SetFailed
        end

        if not value then
            return _delete(row, col)
        end

        if get(row, col) then
            return SetOk
        end
        
        entries.push(recover SparseEntry(row, col) end)

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
        if row > (height - 1) then
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
                set(row, i, value)
                i = i + 1
            end

            SetOk
        else
            SetFailed
        end

    fun _lookup(row: USize, col: USize) : USize ? =>
        // somewhat contrived
        entries.find((recover SparseEntry(row,col) end) where predicate = {
            (l: SparseEntry, r: SparseEntry): Bool => (l.row == r.row) and (l.col == r.col)
        }) ?

    fun ref _delete(row: USize, col: USize) : MatrixResult =>
        try
            let pos = _lookup(row, col) ?
            entries.remove(pos,1)
            SetOk
        else
            SetFailed
        end
