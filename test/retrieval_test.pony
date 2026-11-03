use "pony_test"

use "../htm/measure"

class RetrievalTest is TestList
  fun name(): String => "Retrieval"

  fun tag tests(test: PonyTest) =>
    test(_ANearestClassmateComesFirst)
    test(_ACloserStrangerIsCounted)
    test(_ATieDoesNotCountAgainstTheClassmate)
    test(_NoClassmateAtAllCountsEveryOtherPicture)
    test(_TheOwnClassMeanIgnoresTheOtherClasses)
    test(_TheMeanOfNoValuesIsNought)

class iso _ANearestClassmateComesFirst is UnitTest
  fun name(): String => "retrieval: the nearest picture is a classmate"
  fun apply(h: TestHelper) =>
    let candidates: Array[(USize, String val)] = [(3, "cat"); (9, "dog")]
    h.assert_eq[USize](0, Retrieval.obstacles(candidates, "cat"))

class iso _ACloserStrangerIsCounted is UnitTest
  fun name(): String => "retrieval: a stranger closer than the classmate is counted"
  fun apply(h: TestHelper) =>
    let candidates: Array[(USize, String val)] =
      [(2, "dog"); (5, "cat"); (7, "dog")]
    h.assert_eq[USize](1, Retrieval.obstacles(candidates, "cat"))

class iso _ATieDoesNotCountAgainstTheClassmate is UnitTest
  fun name(): String => "retrieval: a tie with the classmate is not a stranger first"
  fun apply(h: TestHelper) =>
    let candidates: Array[(USize, String val)] = [(4, "dog"); (4, "cat")]
    h.assert_eq[USize](0, Retrieval.obstacles(candidates, "cat"))

class iso _NoClassmateAtAllCountsEveryOtherPicture is UnitTest
  fun name(): String => "retrieval: no classmate at all leaves every picture before it"
  fun apply(h: TestHelper) =>
    let candidates: Array[(USize, String val)] = [(1, "dog"); (2, "bird")]
    h.assert_eq[USize](2, Retrieval.obstacles(candidates, "cat"))

class iso _TheOwnClassMeanIgnoresTheOtherClasses is UnitTest
  fun name(): String => "retrieval: the own-class mean is over the own class only"
  fun apply(h: TestHelper) =>
    let candidates: Array[(USize, String val)] =
      [(2, "cat"); (4, "dog"); (6, "cat")]
    h.assert_eq[F64](4.0, Retrieval.mean_distance(candidates, "cat", true))
    h.assert_eq[F64](4.0, Retrieval.mean_distance(candidates, "cat", false))

class iso _TheMeanOfNoValuesIsNought is UnitTest
  fun name(): String => "retrieval: the mean of no values is nought"
  fun apply(h: TestHelper) =>
    let none: Array[F64] = Array[F64]
    h.assert_eq[F64](0.0, Retrieval.mean(none))
