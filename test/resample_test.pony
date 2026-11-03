use "pony_test"

use "../htm/encoders"
use "../htm/measure"

primitive PictureFixture
  """
  A picture written row by row, so that a test says what the pixels are.
  """
  fun of(rows: Array[Array[U8]] val): GrayscaleImage val ? =>
    GrayscaleImage.from_rows(rows)?

class ResampleTest is TestList
  fun name(): String => "Resampling a picture to a grid"
  fun tag tests(test: PonyTest) =>
    test(_ACellIsTheAverageOfThePixelsItCovers)
    test(_AQuarterOfAGridOfFourIsTheAverageOfItsFourPixels)
    test(_AGridFinerThanThePictureTakesTheNearestPixel)
    test(_ASmallerPictureReadsAsTheSameGridWhenItIsAWholeNumberOfCells)

class iso _ACellIsTheAverageOfThePixelsItCovers is UnitTest
  fun name(): String => "resample: a cell is the average of the pixels it covers"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(
      recover val [[10; 20; 30; 40]; [10; 20; 30; 40]] end)?
    let grid = Resample.block_average(picture, 2, 1)?
    h.assert_eq[F64](15.0, grid(0)?)
    h.assert_eq[F64](35.0, grid(1)?)

class iso _AQuarterOfAGridOfFourIsTheAverageOfItsFourPixels is UnitTest
  fun name(): String => "resample: one cell of a two by two picture averages four pixels"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(recover val [[0; 100]; [200; 255]] end)?
    let grid = Resample.block_average(picture, 1, 1)?
    h.assert_eq[F64](138.75, grid(0)?)

class iso _AGridFinerThanThePictureTakesTheNearestPixel is UnitTest
  fun name(): String => "resample: a grid finer than the picture takes the nearest pixel"
  fun apply(h: TestHelper) ? =>
    let picture = PictureFixture.of(recover val [[0; 255]] end)?
    let grid = Resample.block_average(picture, 4, 1)?
    h.assert_eq[F64](0.0, grid(0)?)
    h.assert_eq[F64](0.0, grid(1)?)
    h.assert_eq[F64](255.0, grid(2)?)
    h.assert_eq[F64](255.0, grid(3)?)

class iso _ASmallerPictureReadsAsTheSameGridWhenItIsAWholeNumberOfCells is UnitTest
  fun name(): String => "resample: a picture and a copy of it twice as wide read the same"
  fun apply(h: TestHelper) ? =>
    let small = Synthetic.pattern(6, 6)?
    let twice = Distortions.scaled(small, 2)?
    let before = Resample.block_average(small, 3, 3)?
    let after = Resample.block_average(twice, 3, 3)?

    h.assert_eq[USize](before.size(), after.size())
    var index: USize = 0
    while index < before.size() do
      h.assert_eq[F64](before(index)?, after(index)?)
      index = index + 1
    end
