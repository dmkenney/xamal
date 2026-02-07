defmodule Xamal.Configuration.Validator do
  @moduledoc """
  Validates the configuration.
  """

  def validate!(%Xamal.Configuration{} = config) do
    validate_service!(config)
    validate_servers!(config)
    validate_retain_releases!(config)
    validate_destination!(config)
    :ok
  end

  defp validate_service!(config) do
    service = Xamal.Configuration.service(config)

    unless Regex.match?(~r/^[a-z0-9_-]+$/i, service) do
      raise ArgumentError,
            "Service name can only include alphanumeric characters, hyphens, and underscores"
    end
  end

  defp validate_servers!(config) do
    if config.roles == [] do
      raise ArgumentError, "No servers specified"
    end

    primary_name = Xamal.Configuration.primary_role_name(config)

    unless Xamal.Configuration.role(config, primary_name) do
      raise ArgumentError, "The primary_role '#{primary_name}' isn't defined"
    end

    primary = Xamal.Configuration.primary_role(config)

    if primary.hosts == [] do
      raise ArgumentError, "No servers specified for the #{primary.name} primary_role"
    end
  end

  defp validate_retain_releases!(config) do
    if Xamal.Configuration.retain_releases(config) < 1 do
      raise ArgumentError, "Must retain at least 1 release"
    end
  end

  defp validate_destination!(config) do
    if Xamal.Configuration.require_destination?(config) and config.destination == nil do
      raise ArgumentError, "You must specify a destination"
    end
  end
end
