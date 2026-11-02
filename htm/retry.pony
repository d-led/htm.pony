primitive Retry
  """
  How long a retry waits.

  A round that closed with bands missing asks those bands again, and the n-th
  retry waits 2^n deadlines: a band that was merely busy answers when it stops
  being busy, and handing it the same deadline again is only asking twice at
  once. The wait doubles rather than growing by a step because a band that took
  twice as long as expected is the ordinary case, and one that took four times as
  long is still worth hearing from.

  Nothing here tells a band that is busy from one that is gone. In one process a
  band is either working or never going to answer, and both look like silence, so
  how many retries a coordinator makes is how patient its caller is - not a
  diagnosis it can reach.
  """
  fun waited(deadline_ms: U64, retry: USize): U64 =>
    """
    How long the n-th retry waits, counting from one. A coordinator that has not
    retried yet is waiting its first deadline, which is the caller's own number.
    """
    var wait = deadline_ms
    var doubling: USize = 1
    while doubling <= retry do
      wait = wait * 2
      doubling = doubling + 1
    end
    wait
