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
