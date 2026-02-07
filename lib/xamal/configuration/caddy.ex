defmodule Xamal.Configuration.Caddy do
  @moduledoc """
  Caddy reverse proxy configuration.
  """

  defstruct [
    :host,
    :hosts,
    :app_port
  ]

  def new(config) when is_map(config) do
    %__MODULE__{
      host: Map.get(config, "host"),
      hosts: Map.get(config, "hosts", []),
      app_port: Map.get(config, "app_port", 4000)
    }
  end

  def new(_), do: %__MODULE__{app_port: 4000, hosts: []}

  @doc """
  Returns all configured hostnames for the Caddyfile.
  """
  def hostnames(%__MODULE__{host: host, hosts: hosts}) do
    all = if host, do: [host | hosts], else: hosts
    Enum.uniq(all)
  end

  @doc """
  The alternate port used during blue-green deploy.
  """
  def alt_port(%__MODULE__{app_port: port}), do: port + 1

  @doc """
  Generate a Caddyfile for the given upstream port.
  """
  def generate_caddyfile(%__MODULE__{} = caddy, upstream_port) do
    caddyfile_block(caddy, "reverse_proxy localhost:#{upstream_port}")
  end

  @doc """
  Generate a maintenance mode Caddyfile.
  """
  def maintenance_caddyfile(%__MODULE__{} = caddy) do
    caddyfile_block(caddy, ~s(respond "Service under maintenance" 503))
  end

  defp caddyfile_block(caddy, directive) do
    matcher =
      case hostnames(caddy) do
        [] -> ":80"
        hosts -> Enum.join(hosts, ", ")
      end

    """
    #{matcher} {
        #{directive}
    }
    """
  end
end
