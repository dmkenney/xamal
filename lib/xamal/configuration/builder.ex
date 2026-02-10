defmodule Xamal.Configuration.Builder do
  @moduledoc """
  Builder configuration: local/docker/remote build settings.
  """

  defstruct [
    :local,
    :docker,
    :remote,
    :args,
    volumes: []
  ]

  def new(config) when is_map(config) do
    %__MODULE__{
      local: Map.get(config, "local", true),
      docker: Map.get(config, "docker", false),
      remote: Map.get(config, "remote"),
      args: Map.get(config, "args", %{}),
      volumes: Map.get(config, "volumes", [])
    }
  end

  def new(_), do: %__MODULE__{local: true, docker: false, args: %{}, volumes: []}

  def local?(%__MODULE__{local: true}), do: true
  def local?(_), do: false

  def docker?(%__MODULE__{docker: docker}) when docker != false and docker != nil, do: true
  def docker?(_), do: false

  @doc """
  Returns the Docker image to use for building.
  If `docker` is a string, it's used as the image name.
  If `docker` is `true`, a default hexpm image is used.
  """
  def docker_image(%__MODULE__{docker: image}) when is_binary(image), do: image
  def docker_image(_), do: "hexpm/elixir:1.18.3-erlang-27.2.3-debian-bookworm-20250113"

  def remote?(%__MODULE__{remote: remote}) when is_binary(remote), do: true
  def remote?(_), do: false
end
