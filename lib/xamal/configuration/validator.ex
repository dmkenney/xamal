defmodule Xamal.Configuration.Validator do
  @moduledoc """
  Validates the configuration.
  """

  alias Xamal.Configuration

  def validate!(%Configuration{} = config) do
    validate_service!(config)
    validate_servers!(config)
    validate_host_names!(config)
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

  # The same host may appear in several roles, but a name must always point at
  # one address and an address must carry at most one name.
  defp validate_host_names!(config) do
    pairs =
      config.roles
      |> Enum.flat_map(fn role -> Map.to_list(role.host_names || %{}) end)
      |> Enum.uniq()

    pairs
    |> Enum.group_by(fn {_address, name} -> name end, fn {address, _name} -> address end)
    |> Enum.each(fn
      {_name, [_]} ->
        :ok

      {name, addresses} ->
        raise ArgumentError,
              "Host name '#{name}' is used for more than one address: #{Enum.join(addresses, ", ")}"
    end)

    pairs
    |> Enum.group_by(fn {address, _name} -> address end, fn {_address, name} -> name end)
    |> Enum.each(fn
      {_address, [_]} ->
        :ok

      {address, names} ->
        raise ArgumentError,
              "Host #{address} has more than one name: #{Enum.join(names, ", ")}"
    end)

    addresses = Configuration.all_hosts(config)

    Enum.each(pairs, fn {address, name} ->
      if name != address and name in addresses do
        raise ArgumentError, "Host name '#{name}' is also the address of another host"
      end
    end)
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
