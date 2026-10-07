defmodule Xamal.Context do
  @moduledoc """
  Runtime deployment context.

  Keeps configuration, host/role filters, verbosity, and lock state together so
  orchestration code can be driven by explicit data instead of process-global
  state.
  """

  defstruct [
    :config,
    :specific_hosts,
    :specific_roles,
    :verbosity,
    holding_lock: false,
    connected: false
  ]

  alias Xamal.Configuration

  @type t :: %__MODULE__{
          config: Configuration.t() | nil,
          specific_hosts: [String.t()] | nil,
          specific_roles: [String.t()] | nil,
          verbosity: :debug | :info | :error | nil,
          holding_lock: boolean(),
          connected: boolean()
        }

  def new(config \\ nil), do: %__MODULE__{config: config}

  def put_config(%__MODULE__{} = context, config), do: %{context | config: config}

  def put_specific_hosts(%__MODULE__{} = context, hosts), do: %{context | specific_hosts: hosts}

  def put_specific_roles(%__MODULE__{} = context, roles), do: %{context | specific_roles: roles}

  def put_verbosity(%__MODULE__{} = context, verbosity), do: %{context | verbosity: verbosity}

  def put_holding_lock(%__MODULE__{} = context, holding_lock) do
    %{context | holding_lock: holding_lock}
  end

  def put_connected(%__MODULE__{} = context, connected), do: %{context | connected: connected}

  def configured?(%__MODULE__{config: config}), do: config != nil

  def hosts(%__MODULE__{config: nil}), do: []

  def hosts(%__MODULE__{} = context) do
    context.config
    |> Configuration.all_hosts()
    |> filter_specific_hosts(context.specific_hosts, Configuration.host_names(context.config))
    |> filter_specific_roles(context)
  end

  @doc """
  Host filter patterns that match no configured host by address or name.
  """
  def unmatched_host_patterns(%__MODULE__{config: nil}, patterns), do: patterns

  def unmatched_host_patterns(%__MODULE__{config: config}, patterns) do
    hosts = Configuration.all_hosts(config)
    names = Configuration.host_names(config)

    Enum.reject(patterns, fn pattern ->
      Enum.any?(hosts, &host_matches?(&1, names, [pattern]))
    end)
  end

  def primary_host(%__MODULE__{config: nil}), do: nil
  def primary_host(%__MODULE__{config: config}), do: Configuration.primary_host(config)

  def roles(%__MODULE__{config: nil}), do: []

  def roles(%__MODULE__{specific_roles: nil, config: config}), do: config.roles

  def roles(%__MODULE__{specific_roles: specific_roles, config: config}) do
    Enum.filter(config.roles, fn role -> matches_any?(role.name, specific_roles) end)
  end

  defp filter_specific_hosts(hosts, nil, _names), do: hosts

  defp filter_specific_hosts(hosts, specific_hosts, names) do
    Enum.filter(hosts, &host_matches?(&1, names, specific_hosts))
  end

  defp host_matches?(host, names, patterns) do
    matches_any?(host, patterns) or
      case Map.get(names, host) do
        nil -> false
        name -> matches_any?(name, patterns)
      end
  end

  defp filter_specific_roles(hosts, %{specific_roles: nil}), do: hosts

  defp filter_specific_roles(hosts, context) do
    role_hosts =
      context.config.roles
      |> Enum.filter(fn role -> matches_any?(role.name, context.specific_roles) end)
      |> Enum.flat_map(& &1.hosts)
      |> Enum.uniq()

    Enum.filter(hosts, &(&1 in role_hosts))
  end

  defp matches_any?(value, patterns) do
    Enum.any?(patterns, fn pattern ->
      pattern
      |> wildcard_regex()
      |> Regex.match?(value)
    end)
  end

  defp wildcard_regex(pattern) do
    pattern = pattern |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.compile!("^#{pattern}$")
  end
end
