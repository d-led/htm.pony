use "pony_test"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)

  new make() => None
  
  fun tag tests(test: PonyTest) =>
    DenseBinaryMatrixTest.tests(test)
    SparseBinaryMatrixTest.tests(test)
    ScalarEncoderTest.tests(test)
    ArrayConversionsTest.tests(test)
    DateEncodingTest.tests(test)
    TopologyTest.tests(test)
    ColumnTest.tests(test)
    InhibitionTest.tests(test)
    SpatialPoolerConfigTest.tests(test)
    SpatialPoolerTest.tests(test)
    BallotBoxTest.tests(test)
    CorticalColumnTest.tests(test)
    ColumnShardTest.tests(test)
    PoolerTest.tests(test)
    ImageEncoderTest.tests(test)
    TemporalMemoryTest.tests(test)
    AnomalyTest.tests(test)
    SDRClassifierTest.tests(test)
    PredictionClassifierTest.tests(test)
    StbDecoderTest.tests(test)
    SpatialPoolerLearningTest.tests(test)
    AnomalyLikelihoodTest.tests(test)
    TemporalRegionTest.tests(test)
    CategoryEncoderTest.tests(test)
    RandomDistributedScalarTest.tests(test)
