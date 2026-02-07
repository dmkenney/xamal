defmodule Xamal.SSH.Host do
  @moduledoc """
  Host struct and helpers for SSH connections.
  """

  @doc """
  Extract the hostname from a host string (may include user@ prefix).
  """
  def hostname(host) when is_binary(host) do
    case String.split(host, "@", parts: 2) do
      [_user, hostname] -> hostname
      [hostname] -> hostname
    end
  end

  @doc """
  Get the port for a host, using ssh config default.
  """
  def port(host, ssh_config) when is_binary(host) do
    case Xamal.Utils.parse_host_port(hostname(host)) do
      {_h, p} when p != 22 -> p
      _ -> ssh_config.port
    end
  end

  @doc """
  Get the user for a host, falling back to ssh config.
  """
  def user(host, ssh_config) when is_binary(host) do
    case String.split(host, "@", parts: 2) do
      [user, _hostname] -> user
      _ -> ssh_config.user
    end
  end
end
