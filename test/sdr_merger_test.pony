use "pony_test"
use "../htm"

class SDRMergerTest is TestList
  fun name(): String => "SDR merger"

  fun tag tests(test: PonyTest) =>
    test(_TheSecondSpaceStartsWhereTheFirstEnds)
    test(_AnEmptySpaceAddsNothing)
    test(_AnOverlapIsMergedRatherThanCountedTwice)
    test(_WhatFitsIsKeptWhole)
    test(_SubsamplingKeepsTheAskedNumberOfPositions)
    test(_SubsamplingForgetsRepeats)
    test(_TheSameSeedChoosesTheSamePositions)

class iso _TheSecondSpaceStartsWhereTheFirstEnds is UnitTest
  fun name(): String => "the two spaces meet where the first one ends"

  fun apply(h: TestHelper) =>
    let merged =
      SDRMerger.concat(recover val [0; 2] end, recover val [1; 3] end, 4)

    h.assert_array_eq[USize]([0; 2; 5; 7], merged)

class iso _AnEmptySpaceAddsNothing is UnitTest
  fun name(): String => "an empty space adds nothing"

  fun apply(h: TestHelper) =>
    let merged =
      SDRMerger.concat(
        recover val [1; 3] end, recover val Array[USize] end, 10)

    h.assert_array_eq[USize]([1; 3], merged)

class iso _AnOverlapIsMergedRatherThanCountedTwice is UnitTest
  fun name(): String => "positions that land on each other are merged"

  fun apply(h: TestHelper) =>
    // the second space begins where the first bit of `right` already sits
    let merged =
      SDRMerger.concat(recover val [0; 5] end, recover val [0; 1] end, 5)

    h.assert_array_eq[USize]([0; 5; 6], merged)

class iso _WhatFitsIsKeptWhole is UnitTest
  fun name(): String => "a representation that already fits is left whole"

  fun apply(h: TestHelper) =>
    let kept = SDRMerger.subsample(recover val [1; 2; 3] end, 5)

    h.assert_array_eq[USize]([1; 2; 3], kept)

class iso _SubsamplingKeepsTheAskedNumberOfPositions is UnitTest
  fun name(): String => "subsampling keeps exactly the number asked for"

  fun apply(h: TestHelper) =>
    let all: Array[USize] val = recover val [0; 1; 2; 3; 4; 5; 6; 7; 8; 9] end
    let kept = SDRMerger.subsample(all, 3, 7)

    h.assert_eq[USize](3, kept.size())
    for index in kept.values() do
      h.assert_true(all.contains(index), "only positions that were there")
    end

class iso _SubsamplingForgetsRepeats is UnitTest
  fun name(): String => "a position named twice is one position"

  fun apply(h: TestHelper) =>
    let kept = SDRMerger.subsample(recover val [1; 1; 2; 2; 3] end, 3)

    h.assert_array_eq[USize]([1; 2; 3], kept)

class iso _TheSameSeedChoosesTheSamePositions is UnitTest
  fun name(): String => "the same seed chooses the same positions"

  fun apply(h: TestHelper) =>
    let all: Array[USize] val =
      recover val [0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11] end

    h.assert_array_eq[USize](
      SDRMerger.subsample(all, 4, 11), SDRMerger.subsample(all, 4, 11))
