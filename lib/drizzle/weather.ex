defmodule Drizzle.Weather do
  @moduledoc """
  This module handles getting the weather forecast.
  """

  @forecast_location Application.get_env(:drizzle, :location, %{
                       latitude: 39.3898838,
                       longitude: -104.8287546
                     })
  @winter_months Application.get_env(:drizzle, :winter_months, [])
  @low_temp 40
  @high_temp 90

  @doc """
  weather_adjustment_factor/0 determines adjustments to make to watering time
  based on the atmospheric conditions.
  """
  @spec weather_adjustment_factor() :: float() | {:error, String.t()}
  def weather_adjustment_factor do
    if month_as_atom(DateTime.utc_now().month) in @winter_months do
      0
    else
      {low, high, precipitation} =
        Drizzle.WeatherData.current_state()
        |> Enum.filter(&(!is_nil(&1)))
        |> weather_info()

      temperature_adjustment(low, high) * precipitation_adjustment(precipitation)
    end
  end

  def get_todays_forecast do
    {:ok, data} =
      Darkskyx.forecast(
        Map.get(@forecast_location, :latitude),
        Map.get(@forecast_location, :longitude),
        %Darkskyx{
          exclude: "currently,minutely"
        }
      )

    data
    |> temps_and_precips()
    |> Enum.slice(0..23)
    |> Drizzle.WeatherData.update()
  end

  defp temperature_adjustment(low, _high) when low <= @low_temp, do: 0
  defp temperature_adjustment(_low, high) when high >= @high_temp, do: 1.33
  defp temperature_adjustment(_low, _high), do: 1

  defp precipitation_adjustment(prec) when prec >= 1.0, do: 0
  defp precipitation_adjustment(prec) when prec >= 0.5, do: 0.75
  defp precipitation_adjustment(prec) when prec >= 0.25, do: 0.5
  defp precipitation_adjustment(_prec), do: 1

  defp temps_and_precips(data) do
    Enum.map(data["hourly"]["data"], fn d ->
      {d["temperature"], d["precipIntensity"], d["precipProbability"]}
    end)
  end

  defp weather_info(data) do
    with {cumulative_amount, cumulative_percent} <-
           Enum.reduce(data, {0, 0}, fn {_, am, pr}, {acc_a, acc_b} ->
             {acc_a + am, acc_b + pr}
           end),
         {low, high} <- Enum.min_max_by(data, fn {temp, _, _} -> temp end),
         rainfall <- cumulative_amount * cumulative_percent do
      {low_temp, _, _} = low
      {high_temp, _, _} = high
      {low_temp, high_temp, rainfall}
    else
      _err -> {:error, "unknown error"}
    end
  end

  defp month_as_atom(num) do
    months_map = %{
      1 => :jan,
      2 => :feb,
      3 => :mar,
      4 => :apr,
      5 => :may,
      6 => :jun,
      7 => :jul,
      8 => :aug,
      9 => :sep,
      10 => :oct,
      11 => :nov,
      12 => :dec
    }

    Map.get(months_map, num)
  end
end
