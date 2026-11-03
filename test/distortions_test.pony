use "pony_test"
use "random"

use "../htm/encoders"
use "../htm/measure"

class DistortionsTest is TestList
  fun name(): String => "The distortions"
  fun tag tests(test: PonyTest) =>
    test(_BrighterHoldsAtWhite)
    test(_DarkerHoldsAtBlack)
    test(_ScalingRepeatsEveryPixel)
    test(_ShrinkingAveragesTheBlockItReplaces)
    test(_CroppingKeepsTheMiddleOfThePicture)
    test(_GrainIsNoughtForNoAmount)

class iso _BrighterHoldsAtWhite is UnitTest
  fun name(): String => "distortions: a brighter copy holds at white"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(recover val [[10; 255]] end)?
    let brighter = Distortions.brighter(picture, 40)?
    h.assert_eq[U8](50, brighter(0, 0)?)
    h.assert_eq[U8](255, brighter(1, 0)?)

class iso _DarkerHoldsAtBlack is UnitTest
  fun name(): String => "distortions: a darker copy holds at black"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(recover val [[10; 250]] end)?
    let darker = Distortions.darker(picture, 40)?
    h.assert_eq[U8](0, darker(0, 0)?)
    h.assert_eq[U8](210, darker(1, 0)?)

class iso _ScalingRepeatsEveryPixel is UnitTest
  fun name(): String => "distortions: scaling repeats every pixel"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(recover val [[10; 200]] end)?
    let twice = Distortions.scaled(picture, 2)?
    h.assert_eq[USize](4, twice.width)
    h.assert_eq[USize](2, twice.height)
    h.assert_eq[U8](10, twice(0, 0)?)
    h.assert_eq[U8](10, twice(1, 1)?)
    h.assert_eq[U8](200, twice(3, 0)?)

class iso _ShrinkingAveragesTheBlockItReplaces is UnitTest
  fun name(): String => "distortions: shrinking averages the block it replaces"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(
      recover val
        [[10; 20; 10; 20]; [20; 10; 20; 10]; [10; 20; 10; 20]; [20; 10; 20; 10]]
      end)?
    let half = Distortions.shrunk(picture, 2)?
    h.assert_eq[USize](2, half.width)
    h.assert_eq[U8](15, half(0, 0)?)
    h.assert_eq[U8](15, half(1, 1)?)

class iso _CroppingKeepsTheMiddleOfThePicture is UnitTest
  fun name(): String => "distortions: cropping keeps the middle of the picture"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(
      recover val [[1; 2; 3]; [4; 5; 6]; [7; 8; 9]] end)?
    let cropped = Distortions.cropped(picture, 1)?
    h.assert_eq[USize](1, cropped.width)
    h.assert_eq[U8](5, cropped(0, 0)?)

class iso _GrainIsNoughtForNoAmount is UnitTest
  fun name(): String => "distortions: no grain leaves the picture as it was"
  fun apply(h: TestHelper) ? =>
    let picture = Synthetic.gradient(32, 32)?
    let same = Distortions.noisy(picture, 0, Rand(7))?
    var differences: USize = 0
    var y: USize = 0
    while y < picture.height do
      var x: USize = 0
      while x < picture.width do
        if picture(x, y)? != same(x, y)? then differences = differences + 1 end
        x = x + 1
      end
      y = y + 1
    end
    h.assert_eq[USize](0, differences)
