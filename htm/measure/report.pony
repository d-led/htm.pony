primitive Report
  """
  Markdown written by the measurement rather than typed in beside it.

  A study prints its numbers as text for a person reading a terminal, and then
  the same numbers as markdown, so that the page quoting them is a copy of what
  the program said and not a transcription of it. `scripts/studies.sh` splits
  the two and keeps the markdown in `docs/results/`, where the documentation
  includes it.

  The table is the record; a chart is a second way of reading it. Anything the
  chart cannot say is said by the table beside it.
  """

  fun table(
    headers: Array[String] val,
    rows: Array[Array[String] val] val)
    : String val
  =>
    """
    A markdown table: one header row, and one row per measurement.
    """
    recover
      let markdown = String
      markdown.append("|")
      for header in headers.values() do
        markdown.append(" " + header + " |")
      end
      markdown.append("\n|")
      for _ in headers.values() do
        markdown.append(" --- |")
      end
      for row in rows.values() do
        markdown.append("\n|")
        for cell in row.values() do
          markdown.append(" " + cell + " |")
        end
      end
      markdown.append("\n")
      markdown
    end

  fun chart(
    title: String,
    y_label: String,
    categories: Array[String] val,
    series: Array[(String, Array[F64] val)] val)
    : String val
  =>
    """
    A mermaid `xychart-beta` block: a category per tick on the x axis, and one
    bar series per measurement.

    Nothing is labelled on the x axis but the categories themselves, so they
    are kept short by the caller - the table above the chart is where the long
    names live.
    """
    recover
      let markdown = String
      markdown.append("```mermaid\nxychart-beta\n")
      markdown.append("    title \"" + title + "\"\n")
      markdown.append("    x-axis [")
      var first: Bool = true
      for category in categories.values() do
        if not first then markdown.append(", ") end
        markdown.append("\"" + category + "\"")
        first = false
      end
      markdown.append("]\n")
      markdown.append("    y-axis \"" + y_label + "\" " + _span(series) + "\n")
      for (_, values) in series.values() do
        markdown.append("    bar [" + _numbers(values) + "]\n")
      end
      markdown.append("```\n")
      markdown
    end

  fun _span(series: Array[(String, Array[F64] val)] val): String val =>
    """
    The y axis from nought to something a little above the largest value, so
    that no bar reaches the top of the frame.
    """
    var largest: F64 = 0.0
    for (_, values) in series.values() do
      for value in values.values() do
        if value > largest then largest = value end
      end
    end
    "0 --> " + (largest * 1.1).ceil().i64().string()

  fun _numbers(values: Array[F64] val): String val =>
    recover
      let numbers = String
      var first: Bool = true
      for value in values.values() do
        if not first then numbers.append(", ") end
        numbers.append(_one(value))
        first = false
      end
      numbers
    end

  fun _one(value: F64): String =>
    let tenths: I64 = (value * 10.0).round().i64()
    (tenths / 10).string() + "." + (tenths % 10).string()
