use "collections"

class val TemporalOutput
  """
  What one step of a temporal memory produced.

  `active_cells` are the cells that are now active, one or more per active
  column. `predictive_cells` are the cells the memory expects to be active at
  the next step, so they describe the future rather than the present.
  `bursting_columns` are the active columns the memory had no prediction for:
  it had to activate every cell in them, because it did not know which one.
  """
  let active_cells: Array[USize] val
  let predictive_cells: Array[USize] val
  let bursting_columns: Array[USize] val

  new val create(
    active_cells': Array[USize] val,
    predictive_cells': Array[USize] val,
    bursting_columns': Array[USize] val)
  =>
    active_cells = active_cells'
    predictive_cells = predictive_cells'
    bursting_columns = bursting_columns'

  fun predicted_columns(params: TemporalMemoryParams val): Array[USize] val =>
    """
    The distinct columns the prediction points at.
    """
    let columns: Array[USize] iso = recover iso Array[USize] end
    let seen = Set[USize]
    for cell in predictive_cells.values() do
      let column = params.column_of(cell)
      if not seen.contains(column) then
        seen.set(column)
        columns.push(column)
      end
    end
    consume columns
