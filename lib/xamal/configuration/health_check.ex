defmodule Xamal.Configuration.HealthCheck do
  @moduledoc """
  Health check configuration for deployment readiness.
  """

  defstruct path: "/health",
            interval: 1,
            timeout: 30

  def new(config) when is_map(config) do
    %__MODULE__{
      path: Map.get(config, "path", "/health"),
      interval: Map.get(config, "interval", 1),
      timeout: Map.get(config, "timeout", 30)
    }
  end

  def new(_), do: %__MODULE__{}
end
