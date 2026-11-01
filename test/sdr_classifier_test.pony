use "pony_test"
use "../htm"

primitive ClassifierFixture
  fun classifier(): SDRClassifier ? =>
    SDRClassifier(2, 16, 0.1)?

  fun teaches(target: SDRClassifier, active: ReadSeq[USize], category: USize) ? =>
    var round: USize = 0
    while round < 20 do
      target.compute(active, category, true)?
      round = round + 1
    end

class SDRClassifierTest is TestList
  fun name(): String => "SDR classifier"

  fun tag tests(test: PonyTest) =>
    test(_AFreshClassifierHasNoPreference)
    test(_ALearnedPatternIsClassified)
    test(_ASecondPatternIsClassifiedDifferently)
    test(_ACategoryOutsideTheClassifierIsRefused)

class iso _AFreshClassifierHasNoPreference is UnitTest
  fun name(): String => "a fresh classifier prefers no category"

  fun apply(h: TestHelper) ? =>
    let classifier = ClassifierFixture.classifier()?
    let probabilities = classifier.compute([0; 3; 7], None, false)?

    h.assert_eq[F64](0.5, probabilities(0)?)
    h.assert_eq[F64](0.5, probabilities(1)?)

class iso _ALearnedPatternIsClassified is UnitTest
  fun name(): String => "a pattern taught one category is classified as that category"

  fun apply(h: TestHelper) ? =>
    let classifier = ClassifierFixture.classifier()?
    ClassifierFixture.teaches(classifier, [0; 1; 2; 3], 0)?

    let probabilities = classifier.compute([0; 1; 2; 3], None, false)?

    h.assert_eq[USize](0, classifier.best())
    h.assert_true(
      probabilities(0)? > 0.9,
      "the taught category should be the likely one, got " + probabilities(0)?.string())

class iso _ASecondPatternIsClassifiedDifferently is UnitTest
  fun name(): String => "two patterns are told apart"

  fun apply(h: TestHelper) ? =>
    let classifier = ClassifierFixture.classifier()?
    ClassifierFixture.teaches(classifier, [0; 1; 2; 3], 0)?
    ClassifierFixture.teaches(classifier, [12; 13; 14; 15], 1)?

    classifier.compute([12; 13; 14; 15], None, false)?
    h.assert_eq[USize](1, classifier.best())

    classifier.compute([0; 1; 2; 3], None, false)?
    h.assert_eq[USize](0, classifier.best())

class iso _ACategoryOutsideTheClassifierIsRefused is UnitTest
  fun name(): String => "a category the classifier does not have is refused"

  fun apply(h: TestHelper) =>
    try
      let classifier = ClassifierFixture.classifier()?
      classifier.compute([0; 1], 9, true)?
      h.fail("a category past the end should be refused")
    end
