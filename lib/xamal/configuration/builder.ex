defmodule Xamal.Configuration.Builder do
  @moduledoc """
  Builder configuration: local/docker/remote build settings.
  """

  defstruct [
    :local,
    :docker,
    :remote,
    :args
  ]

  def new(config) when is_map(config) do
    %__MODULE__{
      local: Map.get(config, "local", true),
      docker: Map.get(config, "docker", false),
      remote: Map.get(config, "remote"),
      args: Map.get(config, "args", %{})
    }
  end

  def new(_), do: %__MODULE__{local: true, docker: false, args: %{}}

  def local?(%__MODULE__{local: true}), do: true
  def local?(_), do: false

  def docker?(%__MODULE__{docker: true}), do: true
  def docker?(_), do: false

  def remote?(%__MODULE__{remote: remote}) when is_binary(remote), do: true
  def remote?(_), do: false
end
