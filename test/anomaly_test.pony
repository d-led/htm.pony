use "pony_test"
use "../htm"

primitive AnomalyFixture
  """
  A detector over 64-bit inputs, with six columns lighting up per input.
  """

  fun detector(): StreamingAnomalyDetector ? =>
    let pooler = SpatialPooler(SpatialPoolerConfig([64], [64], true, 16.0, 0.1), 42)?
    let memory = TemporalMemory(TemporalMemoryParams(64, 8, 1, 0.5, 0.5, 0.1, 0.02, 32, 4))
    StreamingAnomalyDetector(pooler, memory)

  fun input(bits: ReadSeq[USize]): Array[Bool] =>
    let values = Array[Bool].init(false, 64)
    for bit in bits.values() do
      try values(bit)? = true end
    end
    values

  fun first(): Array[Bool] => input([0; 1; 2; 3; 8; 9])
  fun second(): Array[Bool] => input([16; 17; 18; 19; 24; 25])
  fun third(): Array[Bool] => input([32; 33; 34; 35; 40; 41])
  fun novel(): Array[Bool] => input([48; 49; 50; 51; 56; 57])

class AnomalyTest is TestList
  fun name(): String => "Streaming anomaly"

  fun tag tests(test: PonyTest) =>
    test(_TheFirstInputIsEntirelySurprising)
    test(_ARepeatingSequenceStopsBeingSurprising)
    test(_AnInputOutsideTheSequenceIsSurprisingAgain)

class iso _TheFirstInputIsEntirelySurprising is UnitTest
  fun name(): String => "the first input of a stream is entirely surprising"

  fun apply(h: TestHelper) ? =>
    let detector = AnomalyFixture.detector()?

    h.assert_eq[F64](1.0, detector.observe(AnomalyFixture.first())?)

class iso _ARepeatingSequenceStopsBeingSurprising is UnitTest
  fun name(): String => "a sequence that repeats stops being surprising"

  fun apply(h: TestHelper) ? =>
    let detector = AnomalyFixture.detector()?

    var round: USize = 0
    while round < 12 do
      detector.observe(AnomalyFixture.first())?
      detector.observe(AnomalyFixture.second())?
      detector.observe(AnomalyFixture.third())?
      round = round + 1
    end

    let last = detector.observe(AnomalyFixture.first())?
    h.assert_true(
      last < 0.5,
      "a sequence seen twelve times should mostly be expected, got " + last.string())

class iso _AnInputOutsideTheSequenceIsSurprisingAgain is UnitTest
  fun name(): String => "an input outside the learned sequence is surprising again"

  fun apply(h: TestHelper) ? =>
    let detector = AnomalyFixture.detector()?

    var round: USize = 0
    while round < 12 do
      detector.observe(AnomalyFixture.first())?
      detector.observe(AnomalyFixture.second())?
      detector.observe(AnomalyFixture.third())?
      round = round + 1
    end

    let typical = detector.observe(AnomalyFixture.first())?
    let surprise = detector.observe(AnomalyFixture.novel())?

    h.assert_true(
      surprise > typical,
      "a novel input should score higher than the learned one, got "
        + surprise.string() + " against " + typical.string())
    h.assert_true(
      surprise > 0.5,
      "a novel input should be clearly surprising, got " + surprise.string())
