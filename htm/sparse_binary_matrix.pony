use "collections"

//entries are positions of non-zero values
class val SparseEntry
    let row: USize
    let col: USize

    new create(row': USize, col': USize) =>
        row = row'
        col = col'


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