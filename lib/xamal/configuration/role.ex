defmodule Xamal.Configuration.Role do
  @moduledoc """
  Role configuration.

  Each role has a name, a list of hosts, optional cmd override,
  and optional env overrides.

  A host entry is either a bare address (`"10.0.0.1"`) or a single
  `%{name => address}` map. `hosts` always holds addresses; `host_names`
  maps an address to its name for hosts that have one.
  """

  defstruct [:name, :hosts, :cmd, :env, :tags, :config, host_names: %{}]

  alias Xamal.Configuration.Env

  @doc """
  Create a role from the servers config entry.
  """
  def new(name, role_config, raw_config, secrets) do
    {entries, specializations} = parse_role_config(role_config)
    {hosts, host_names} = parse_hosts(name, entries)

    specialized_env =
      case Map.get(specializations, "env") do
        nil -> nil
        env_config -> Env.new(env_config, secrets)
      end

    %__MODULE__{
      name: name,
      hosts: hosts,
      host_names: host_names,
      cmd: Map.get(specializations, "cmd"),
      env: specialized_env,
      tags: Map.get(specializations, "tags", []),
      config: raw_config
    }
  end

  def primary_host(%__MODULE__{hosts: [first | _]}), do: first
  def primary_host(%__MODULE__{hosts: []}), do: nil

  @doc """
  Get the resolved env for a host, merging global + role env.
  """
  def resolved_env(%__MODULE__{env: nil}, global_env), do: global_env
  def resolved_env(%__MODULE__{env: role_env}, global_env), do: Env.merge(global_env, role_env)

  @doc """
  The secrets env file path on the remote server.
  """
  def secrets_path(%__MODULE__{name: name}, config) do
    "#{Xamal.Configuration.env_directory(config)}/roles/#{name}.env"
  end

  # Private

  defp parse_role_config(config) when is_list(config) do
    # Simple list of hosts
    {config, %{}}
  end

  defp parse_role_config(config) when is_map(config) do
    hosts =
      case Map.get(config, "hosts") do
        nil -> []
        hosts when is_list(hosts) -> hosts
      end

    specializations = Map.drop(config, ["hosts"])
    {hosts, specializations}
  end

  defp parse_role_config(_), do: {[], %{}}

  defp parse_hosts(role_name, entries) do
    entries
    |> Enum.flat_map(&host_entry(role_name, &1))
    |> Enum.reduce({[], %{}}, fn
      {nil, address}, {hosts, names} ->
        {[address | hosts], names}

      {name, address}, {hosts, names} ->
        case Map.fetch(names, address) do
          {:ok, existing} when existing != name ->
            raise ArgumentError,
                  "Host #{address} has more than one name: #{existing}, #{name}"

          _ ->
            {[address | hosts], Map.put(names, address, name)}
        end
    end)
    |> then(fn {hosts, names} -> {Enum.reverse(hosts), names} end)
  end

  defp host_entry(_role_name, address) when is_binary(address), do: [{nil, address}]

  defp host_entry(role_name, entry) when is_map(entry) do
    entry
    |> Enum.sort()
    |> Enum.map(fn
      {name, address} when is_binary(address) ->
        {to_string(name), address}

      {name, value} ->
        raise ArgumentError,
              "Host #{inspect(to_string(name))} in role #{role_name} must map to an address string, got: #{inspect(value)}"
    end)
  end

  defp host_entry(role_name, entry) do
    raise ArgumentError, "Invalid host in role #{role_name}: #{inspect(entry)}"
  end
end
