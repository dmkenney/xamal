defmodule Xamal.Configuration.Role do
  @moduledoc """
  Role configuration.

  Each role has a name, a list of hosts, optional cmd override,
  and optional env overrides.
  """

  defstruct [:name, :hosts, :cmd, :env, :tags, :config]

  alias Xamal.Configuration.Env

  @doc """
  Create a role from the servers config entry.
  """
  def new(name, role_config, raw_config, secrets) do
    {hosts, specializations} = parse_role_config(role_config)

    specialized_env =
      case Map.get(specializations, "env") do
        nil -> nil
        env_config -> Env.new(env_config, secrets)
      end

    %__MODULE__{
      name: name,
      hosts: hosts,
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
        hosts when is_list(hosts) -> parse_hosts(hosts)
      end

    specializations = Map.drop(config, ["hosts"])
    {hosts, specializations}
  end

  defp parse_role_config(_), do: {[], %{}}

  defp parse_hosts(hosts) do
    Enum.map(hosts, fn
      host when is_binary(host) -> host
      host when is_map(host) -> host |> Map.keys() |> hd()
    end)
  end
end
