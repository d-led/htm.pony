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
