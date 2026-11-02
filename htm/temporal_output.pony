use "collections"

class val TemporalOutput
  """
  What one step of a temporal memory produced.

  `active_cells` are the cells that are now active, one or more per active
  column. `predictive_cells` are the cells the memory expects to be active at
  the next step, so they describe the future rather than the present.
  `bursting_columns` are the active columns the memory had no prediction for:
  it had to activate every cell in them, because it did not know which one.

  `missing` names the bands of a region that never answered, so a step that was
  decided without part of the memory says so. A memory in process never misses
  anything, and a region without a deadline waits rather than deciding early.
  """
  let active_cells: Array[USize] val
  let predictive_cells: Array[USize] val
  let bursting_columns: Array[USize] val
  let missing: Array[USize] val

  new val create(
    active_cells': Array[USize] val,
    predictive_cells': Array[USize] val,
    bursting_columns': Array[USize] val,
    missing': Array[USize] val = [])
  =>
    active_cells = active_cells'
    predictive_cells = predictive_cells'
    bursting_columns = bursting_columns'
    missing = missing'

  fun active_columns(params: TemporalMemoryParams val): Array[USize] val =>
    """
    The distinct columns the active cells belong to.
    """
    _columns_of(active_cells, params)

  fun predicted_columns(params: TemporalMemoryParams val): Array[USize] val =>
    """
    The distinct columns the prediction points at.
    """
    _columns_of(predictive_cells, params)

  fun anomaly(params: TemporalMemoryParams val): F64 =>
    """
    The share of the active columns the memory did not predict.

    This is the streaming anomaly reading: a column that bursts is a prediction
    that failed, so zero means everything that happened was expected and one
    means nothing was. It is a property of this step alone; a run of them is
    what tells you whether something is wrong.
    """
    let active = active_columns(params)
    if active.size() == 0 then return 0.0 end
    bursting_columns.size().f64() / active.size().f64()

  fun _columns_of(cells: ReadSeq[USize], params: TemporalMemoryParams val): Array[USize] val =>
    let columns: Array[USize] iso = recover iso Array[USize] end
    let seen = Set[USize]
    for cell in cells.values() do
      let column = params.column_of(cell)
      if not seen.contains(column) then
        seen.set(column)
        columns.push(column)
      end
    end
    consume columns
