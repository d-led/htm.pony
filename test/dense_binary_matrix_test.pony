use "ponytest"

class DenseBinaryMatrixTest is TestList
  fun name(): String => "Dense binary matrix"
  
  fun tag tests(test: PonyTest) =>
    test(_DenseGetSet)

class iso _DenseGetSet is UnitTest
  fun name(): String => "setting and getting values"

  fun apply(h: TestHelper) =>
    h.assert_eq[U32](4, 2 + 2)
