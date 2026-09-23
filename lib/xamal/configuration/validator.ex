defmodule Xamal.Configuration.Validator do
  @moduledoc """
  Validates the configuration.
  """

  alias Xamal.Configuration

  def validate!(%Configuration{} = config) do
    validate_service!(config)
    validate_servers!(config)
    validate_retain_releases!(config)
    validate_destination!(config)
    validate_ssh_proxy!(config)
    :ok
  end

  defp validate_ssh_proxy!(%{ssh: %{proxy: proxy, proxy_command: command}})
       when is_binary(proxy) and is_binary(command) do
    raise ArgumentError, "Set only one of ssh.proxy and ssh.proxy_command"
  end

  defp validate_ssh_proxy!(_config), do: :ok

  defp validate_service!(config) do
    service = Configuration.service(config)

    unless Regex.match?(~r/^[a-z0-9_-]+$/i, service) do
      raise ArgumentError,
            "Service name can only include alphanumeric characters, hyphens, and underscores"
    end
  end

  defp validate_servers!(config) do
    if config.roles == [] do
      raise ArgumentError, "No servers specified"
    end

    primary_name = Configuration.primary_role_name(config)

    unless Configuration.role(config, primary_name) do
      raise ArgumentError, "The primary_role '#{primary_name}' isn't defined"
    end

    primary = Configuration.primary_role(config)

    if primary.hosts == [] do
      raise ArgumentError, "No servers specified for the #{primary.name} primary_role"
    end
  end

  defp validate_retain_releases!(config) do
    if Configuration.retain_releases(config) < 1 do
      raise ArgumentError, "Must retain at least 1 release"
    end
  end

  defp validate_destination!(config) do
    if Configuration.require_destination?(config) and config.destination == nil do
      raise ArgumentError, "You must specify a destination"
    end
  end
end
