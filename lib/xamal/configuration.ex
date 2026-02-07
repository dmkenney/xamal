defmodule Xamal.Configuration do
  @moduledoc """
  Main configuration module.

  Loads deploy.yml (with EEx template evaluation), merges destination
  overrides, and provides access to all sub-configurations.
  """

  defstruct [
    :raw_config,
    :destination,
    :version,
    :secrets,
    :servers,
    :roles,
    :boot,
    :builder,
    :caddy,
    :env,
    :ssh,
    :release,
    :health_check,
    :aliases
  ]

  alias Xamal.Configuration.{
    Boot,
    Builder,
    Caddy,
    Env,
    HealthCheck,
    Release,
    Role,
    Servers,
    Ssh,
    Validator
  }

  @doc """
  Create configuration from a YAML config file.
  """
  def create_from(opts \\ []) do
    config_file = Keyword.get(opts, :config_file, "config/deploy.yml")
    destination = Keyword.get(opts, :destination)
    version = Keyword.get(opts, :version)

    raw_config = load_config_files(config_file, destination)
    new(raw_config, destination: destination, version: version)
  end

  @doc """
  Create configuration from a raw config map.
  """
  def new(raw_config, opts \\ []) do
    destination = Keyword.get(opts, :destination)
    version = Keyword.get(opts, :version)

    secrets =
      Xamal.Secrets.new(
        destination: destination,
        secrets_path: Map.get(raw_config, "secrets_path", ".xamal/secrets")
      )

    server_config = Servers.new(Map.get(raw_config, "servers"))

    roles =
      server_config.roles
      |> Enum.map(fn {name, role_config} ->
        Role.new(name, role_config, raw_config, secrets)
      end)

    env_config = Env.new(Map.get(raw_config, "env", %{}), secrets)

    config = %__MODULE__{
      raw_config: raw_config,
      destination: destination,
      version: version || version_from_config(raw_config),
      secrets: secrets,
      servers: server_config,
      roles: roles,
      boot: Boot.new(Map.get(raw_config, "boot", %{})),
      builder: Builder.new(Map.get(raw_config, "builder", %{})),
      caddy: Caddy.new(Map.get(raw_config, "caddy", %{})),
      env: env_config,
      ssh: Ssh.new(Map.get(raw_config, "ssh", %{})),
      release: Release.new(Map.get(raw_config, "release", %{}), raw_config),
      health_check: HealthCheck.new(Map.get(raw_config, "health_check", %{})),
      aliases: parse_aliases(Map.get(raw_config, "aliases", %{}))
    }

    Validator.validate!(config)
    config
  end

  # Accessors

  def service(%__MODULE__{raw_config: raw}), do: Map.fetch!(raw, "service")

  def hooks_path(%__MODULE__{raw_config: raw}), do: Map.get(raw, "hooks_path", ".xamal/hooks")

  def secrets_path(%__MODULE__{raw_config: raw}),
    do: Map.get(raw, "secrets_path", ".xamal/secrets")

  def readiness_delay(%__MODULE__{raw_config: raw}), do: Map.get(raw, "readiness_delay", 7)

  def deploy_timeout(%__MODULE__{raw_config: raw}), do: Map.get(raw, "deploy_timeout", 30)

  def drain_timeout(%__MODULE__{raw_config: raw}), do: Map.get(raw, "drain_timeout", 30)

  def retain_releases(%__MODULE__{raw_config: raw}), do: Map.get(raw, "retain_releases", 5)

  def require_destination?(%__MODULE__{raw_config: raw}),
    do: Map.get(raw, "require_destination", false)

  def primary_role_name(%__MODULE__{raw_config: raw}), do: Map.get(raw, "primary_role", "web")

  def primary_role(%__MODULE__{} = config) do
    name = primary_role_name(config)
    Enum.find(config.roles, fn role -> role.name == name end)
  end

  def primary_host(%__MODULE__{} = config) do
    case primary_role(config) do
      nil -> nil
      role -> Role.primary_host(role)
    end
  end

  def all_hosts(%__MODULE__{roles: roles}) do
    roles
    |> Enum.flat_map(fn role -> role.hosts end)
    |> Enum.uniq()
  end

  def app_hosts(%__MODULE__{} = config), do: all_hosts(config)

  def role(%__MODULE__{roles: roles}, name) do
    Enum.find(roles, fn r -> r.name == name end)
  end

  def service_and_destination(%__MODULE__{destination: nil} = config), do: service(config)

  def service_and_destination(%__MODULE__{destination: dest} = config),
    do: "#{service(config)}-#{dest}"

  # Server directories
  def base_directory, do: "/opt/xamal"

  def service_directory(%__MODULE__{} = config) do
    "#{base_directory()}/#{service(config)}"
  end

  def releases_directory(%__MODULE__{} = config) do
    "#{service_directory(config)}/releases"
  end

  def current_link(%__MODULE__{} = config) do
    "#{service_directory(config)}/current"
  end

  def env_directory(%__MODULE__{} = config) do
    "#{service_directory(config)}/env"
  end

  def shared_directory(%__MODULE__{} = config) do
    "#{service_directory(config)}/shared"
  end

  def run_directory, do: "~/.xamal"

  def lock_directory(%__MODULE__{} = config) do
    "#{run_directory()}/lock-#{service(config)}"
  end

  def audit_log_path(%__MODULE__{} = config) do
    "#{run_directory()}/#{service(config)}-audit.log"
  end

  # Private

  defp load_config_files(config_file, destination) do
    base = load_config_file(config_file)

    if destination do
      dest_file = String.replace(config_file, ".yml", ".#{destination}.yml")

      if File.exists?(dest_file) do
        dest_config = load_config_file(dest_file)
        deep_merge(base, dest_config)
      else
        base
      end
    else
      base
    end
  end

  defp load_config_file(file) do
    unless File.exists?(file) do
      raise "Configuration file not found: #{file}"
    end

    content = File.read!(file)

    # Provide `env` as a map binding so deploy.yml can use <%= env["SECRET_KEY"] %>
    # System.get_env("FOO") also works since EEx evaluates Elixir code
    evaluated = EEx.eval_string(content, env: System.get_env())

    case YamlElixir.read_from_string(evaluated) do
      {:ok, config} -> config
      {:error, reason} -> raise "Failed to parse #{file}: #{inspect(reason)}"
    end
  end

  defp version_from_config(_raw_config) do
    System.get_env("VERSION") || Xamal.Utils.version_from_git()
  end

  defp parse_aliases(aliases) when is_map(aliases), do: aliases

  defp parse_aliases(_), do: %{}

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right
end
