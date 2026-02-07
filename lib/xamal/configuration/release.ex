defmodule Xamal.Configuration.Release do
  @moduledoc """
  Elixir release configuration.
  """

  defstruct [:name, :mix_env]

  def new(config, raw_config) when is_map(config) do
    service = Map.get(raw_config, "service", "app")

    %__MODULE__{
      name: Map.get(config, "name", Xamal.Utils.to_release_name(service)),
      mix_env: Map.get(config, "mix_env", "prod")
    }
  end

  def new(_, raw_config), do: new(%{}, raw_config)

  @doc """
  The release binary path within a release directory.
  """
  def bin_path(%__MODULE__{name: name}) do
    "bin/#{name}"
  end
end
