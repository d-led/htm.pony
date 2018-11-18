primitive N
primitive Radius
primitive Resolution

type ScalarOutputType is (N | Radius | Resolution)

// entries are positions of non-zero values
class val ScalarEncoderParams
    let width:      USize
    let min_val:     F64
    let max_val:     F64
    let periodic:   Bool
    let output_type: ScalarOutputType
    let range:      F64
    let resolution: F64
    let name:       String
    let radius:     F64
    let clip_input:  Bool
    let verbosity:  U8
    let n:          USize

    new val create(
        width': USize,
        min_val': F64,
        max_val': F64,
        periodic': Bool = false,
        output_type': ScalarOutputType = N,
        range': F64 = 0.0,
        resolution': F64 = 0.0,
        name': String = "",
        radius': F64 = 0.0 ,
        clip_input': Bool = false,
        verbosity': U8 = 0,
        n': USize = 0
    ) =>
        width = width'
        min_val = min_val'
        max_val = max_val'
        periodic = periodic'
        output_type = output_type'
        range = range'
        resolution = resolution'
        name = name'
        radius = radius'
        clip_input = clip_input'
        verbosity = verbosity'
        n = n'
