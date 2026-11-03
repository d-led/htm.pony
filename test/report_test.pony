use "pony_test"

use "../htm/measure"

class ReportTest is TestList
  fun name(): String => "Markdown written by a measurement"
  fun tag tests(test: PonyTest) =>
    test(_ATableHasAHeaderAndARow)
    test(_AChartNamesItsCategoriesAndDrawsEverySeries)

class iso _ATableHasAHeaderAndARow is UnitTest
  fun name(): String => "report: a table is a header row and one row per measurement"
  fun apply(h: TestHelper) =>
    let headers: Array[String val] val = ["method"; "missed"]
    let rows: Array[Array[String] val] val =
      recover val
        [["last input"; "22.3%"]; ["temporal memory"; "2.9%"]]
      end
    h.assert_eq[String](
      "| method | missed |\n| --- | --- |\n| last input | 22.3% |\n"
        + "| temporal memory | 2.9% |\n",
      Report.table(headers, rows))

class iso _AChartNamesItsCategoriesAndDrawsEverySeries is UnitTest
  fun name(): String => "report: a chart names its categories and draws every series"
  fun apply(h: TestHelper) =>
    let categories: Array[String val] val = ["bright"; "crop"]
    let series: Array[(String, Array[F64] val)] val =
      recover val
        [("difference", [0.0; 23.8]); ("average", [0.0; 19.1])]
      end
    let chart = Report.chart("drift", "% of bits", categories, series)

    h.assert_true(chart.contains("xychart-beta"))
    h.assert_true(chart.contains("\"bright\", \"crop\""))
    h.assert_true(chart.contains("bar [0.0, 23.8]"))
    h.assert_true(chart.contains("bar [0.0, 19.1]"))
    h.assert_true(chart.contains("```"))
