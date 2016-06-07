"""
`transform_data(m::AbstractModel, levels::DataFrame, population_mnemonic = :CNP16OV)`

Transform data loaded in levels and order columns appropriately for the DSGE model.

## Parameters
- `m::AbstractModel`: the model object
- `levels::DataFrame`: data loaded in levels (for instance, the output of `load_data`)

## Optional Arguments

- `population_mnemonic`: the name of the column in `levels` that holds
  the population measure for computing per-capita values. By default,
  it is CNP16OV (Civilian Noninstitutional Population, in thousands, obtained via the FRED API).
"""
function transform_data(m::AbstractModel, levels::DataFrame, population_mnemonic = :CNP16OV)

    n_obs, _ = size(levels)

    # Step 1: HP filter population forecasts, if they're being used

    # population_recorded: historical population, unfiltered
    # population_all: full unfiltered series (including forecast)
    # dlpopulation_forecast: growth rates of population forecasts pre-filtering

    population_recorded = levels[:,[:date, population_mnemonic]]
    population_all, dlpopulation_forecast, n_population_forecast_obs = if use_population_forecast(m)

        # load population forecast
        population_forecast_file = inpath(m, "data", "population_forecast_$(data_vintage(m)).csv")
        pop_forecast = readtable(population_forecast_file)

        rename!(pop_forecast, :POPULATION,  population_mnemonic)
        DSGE.na2nan!(pop_forecast)
        DSGE.format_dates!(:date, pop_forecast)

        # use our "real" series as current value
        pop_all = [population_recorded; pop_forecast[2:end,:]]
        pop_all[population_mnemonic], difflog(pop_forecast[population_mnemonic]), length(pop_forecast[population_mnemonic])
    else
        population_recorded[:,population_mnemonic], _, 1
    end

    # hp filter
    population_all = convert(Array, population_all)
    filtered_population, _ = hpfilter(population_all, 1600)

    # filtered series (levels)
    filtered_population_recorded     = filtered_population[1:end-n_population_forecast_obs+1]     # filtered recorded population series
    filtered_population_forecast     = filtered_population[end-n_population_forecast_obs+1:end]   # filtered forecast population series

    # filtered growth rates 
    dlpopulation_recorded            = difflog(population_recorded[population_mnemonic])
    dlfiltered_population_recorded   = difflog(filtered_population_recorded)

    levels[:filtered_population]          = filtered_population_recorded
    levels[:filtered_population_growth]   = dlfiltered_population_recorded
    levels[:unfiltered_population_growth] = dlpopulation_recorded

    # Step 2: apply transformations to each series
    transformed = DataFrame()
    transformed[:date] = levels[:date]

    for series in keys(m.data_transforms)
        f = m.data_transforms[series]
        transformed[series] = f(levels)
    end

    sort!(transformed, cols = :date)
end