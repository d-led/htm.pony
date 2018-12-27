use "time"

interface Clock
  fun now(): (I64 /*sec*/, U32 /*nsec*/)

class SystemClock is Clock

  fun now(): (I64 /*sec*/, U32 /*nsec*/) =>
    let n = Time.now()
    (n._1, n._2.u32())
