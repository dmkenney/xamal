defmodule Xamal.Configuration.Boot do
  @moduledoc """
  Boot configuration: limit, wait, parallel_roles.
  """

  defstruct limit: nil, wait: nil, parallel_roles: false

  def new(config) when is_map(config) do
    %__MODULE__{
      limit: parse_limit(Map.get(config, "limit")),
      wait: Map.get(config, "wait"),
      parallel_roles: Map.get(config, "parallel_roles", false)
    }
  end

  def new(_), do: %__MODULE__{}

  defp parse_limit(nil), do: nil

  defp parse_limit(limit) when is_binary(limit) do
    if String.ends_with?(limit, "%") do
      {:percent, String.trim_trailing(limit, "%") |> String.to_integer()}
    else
      String.to_integer(limit)
    end
  end

  defp parse_limit(limit) when is_integer(limit), do: limit

  @doc """
  Resolve the limit to an actual number given a host count.
  """
  def resolved_limit(%__MODULE__{limit: nil}, _host_count), do: nil

  def resolved_limit(%__MODULE__{limit: {:percent, pct}}, host_count),
    do: max(div(host_count * pct, 100), 1)

  def resolved_limit(%__MODULE__{limit: limit}, _host_count), do: limit
end
