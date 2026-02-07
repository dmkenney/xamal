defmodule Xamal.Commander do
  @moduledoc """
  Runtime state agent holding configuration, host/role filtering,
  and deploy lock status.

  Equivalent to Kamal's global KAMAL commander singleton.
  """

  use Agent

  defstruct [
    :config,
    :specific_hosts,
    :specific_roles,
    :verbosity,
    holding_lock: false,
    connected: false
  ]

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %__MODULE__{} end, name: Keyword.get(opts, :name, __MODULE__))
  end

  def configure(config, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.update(name, fn state -> %{state | config: config} end)
  end

  def config(name \\ __MODULE__) do
    Agent.get(name, & &1.config)
  end

  def configured?(name \\ __MODULE__) do
    Agent.get(name, & &1.config) != nil
  end

  def set_specific_hosts(hosts, name \\ __MODULE__) do
    Agent.update(name, fn state -> %{state | specific_hosts: hosts} end)
  end

  def set_specific_roles(roles, name \\ __MODULE__) do
    Agent.update(name, fn state -> %{state | specific_roles: roles} end)
  end

  def set_verbosity(verbosity, name \\ __MODULE__) do
    Agent.update(name, fn state -> %{state | verbosity: verbosity} end)
  end

  def holding_lock?(name \\ __MODULE__) do
    Agent.get(name, & &1.holding_lock)
  end

  def set_holding_lock(value, name \\ __MODULE__) do
    Agent.update(name, fn state -> %{state | holding_lock: value} end)
  end

  def connected?(name \\ __MODULE__) do
    Agent.get(name, & &1.connected)
  end

  def set_connected(value, name \\ __MODULE__) do
    Agent.update(name, fn state -> %{state | connected: value} end)
  end

  @doc """
  Get the filtered hosts based on specific_hosts/specific_roles settings.
  """
  def hosts(name \\ __MODULE__) do
    state = Agent.get(name, & &1)
    config = state.config

    all_hosts = Xamal.Configuration.all_hosts(config)

    hosts =
      case state.specific_hosts do
        nil -> all_hosts
        specific -> filter_hosts(all_hosts, specific)
      end

    case state.specific_roles do
      nil ->
        hosts

      specific_roles ->
        role_hosts =
          config.roles
          |> Enum.filter(fn role -> matches_any?(role.name, specific_roles) end)
          |> Enum.flat_map(& &1.hosts)
          |> Enum.uniq()

        Enum.filter(hosts, fn h -> h in role_hosts end)
    end
  end

  @doc """
  Get the primary host.
  """
  def primary_host(name \\ __MODULE__) do
    config = config(name)
    Xamal.Configuration.primary_host(config)
  end

  @doc """
  Get the filtered roles.
  """
  def roles(name \\ __MODULE__) do
    state = Agent.get(name, & &1)
    config = state.config

    case state.specific_roles do
      nil -> config.roles
      specific -> Enum.filter(config.roles, fn role -> matches_any?(role.name, specific) end)
    end
  end

  defp filter_hosts(all_hosts, specific) do
    Enum.filter(all_hosts, fn host -> matches_any?(host, specific) end)
  end

  defp matches_any?(value, patterns) do
    Enum.any?(patterns, fn pattern ->
      if String.contains?(pattern, "*") do
        # Simple wildcard match
        regex_str = pattern |> Regex.escape() |> String.replace("\\*", ".*")
        Regex.match?(~r/^#{regex_str}$/, value)
      else
        value == pattern
      end
    end)
  end
end
