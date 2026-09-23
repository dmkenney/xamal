defmodule Xamal.Configuration do
  @moduledoc """
  Main configuration module.

  Loads config/xamal.exs, merges destination overrides, and provides access to all
  sub-configurations.
  """

  defstruct [
    :raw_config,
    :service,
    :destination,
    :version,
    :hooks_path,
    :secrets_path,
    :readiness_delay,
    :deploy_timeout,
    :drain_timeout,
    :retain_releases,
    :require_destination,
    :primary_role_name,
    :secrets,
    :servers,
    :roles,
    :boot,
    :builder,
    :caddy,
    :env,
    :ssh,
    :release,
    :health_check
  ]

  @type t :: %__MODULE__{}

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
  Create configuration from an Elixir config file.
  """
  def create_from(opts \\ []) do
    config_file = Keyword.get(opts, :config_file, "config/xamal.exs")
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
      service: Map.fetch!(raw_config, "service"),
      destination: destination,
      version: version || version_from_config(raw_config),
      hooks_path: Map.get(raw_config, "hooks_path", ".xamal/hooks"),
      secrets_path: Map.get(raw_config, "secrets_path", ".xamal/secrets"),
      readiness_delay: Map.get(raw_config, "readiness_delay", 7),
      deploy_timeout: Map.get(raw_config, "deploy_timeout", 30),
      drain_timeout: Map.get(raw_config, "drain_timeout", 30),
      retain_releases: Map.get(raw_config, "retain_releases", 5),
      require_destination: Map.get(raw_config, "require_destination", false),
      primary_role_name: Map.get(raw_config, "primary_role", "web"),
      secrets: secrets,
      servers: server_config,
      roles: roles,
      boot: Boot.new(Map.get(raw_config, "boot", %{})),
      builder: Builder.new(Map.get(raw_config, "builder", %{})),
      caddy: Caddy.new(Map.get(raw_config, "caddy", %{})),
      env: env_config,
      ssh: Ssh.new(Map.get(raw_config, "ssh", %{})),
      release: Release.new(Map.get(raw_config, "release", %{}), raw_config),
      health_check: HealthCheck.new(Map.get(raw_config, "health_check", %{}))
    }

    Validator.validate!(config)
    config
  end

  # Accessors

  def service(%__MODULE__{service: service}) when is_binary(service), do: service
  def service(%__MODULE__{raw_config: raw}), do: Map.fetch!(raw, "service")

  def hooks_path(%__MODULE__{hooks_path: hooks_path}) when is_binary(hooks_path), do: hooks_path
  def hooks_path(%__MODULE__{raw_config: raw}), do: Map.get(raw, "hooks_path", ".xamal/hooks")

  def secrets_path(%__MODULE__{secrets_path: secrets_path}) when is_binary(secrets_path),
    do: secrets_path

  def secrets_path(%__MODULE__{raw_config: raw}),
    do: Map.get(raw, "secrets_path", ".xamal/secrets")

  def readiness_delay(%__MODULE__{readiness_delay: readiness_delay})
      when is_integer(readiness_delay),
      do: readiness_delay

  def readiness_delay(%__MODULE__{raw_config: raw}), do: Map.get(raw, "readiness_delay", 7)

  def deploy_timeout(%__MODULE__{deploy_timeout: deploy_timeout}) when is_integer(deploy_timeout),
    do: deploy_timeout

  def deploy_timeout(%__MODULE__{raw_config: raw}), do: Map.get(raw, "deploy_timeout", 30)

  def drain_timeout(%__MODULE__{drain_timeout: drain_timeout}) when is_integer(drain_timeout),
    do: drain_timeout

  def drain_timeout(%__MODULE__{raw_config: raw}), do: Map.get(raw, "drain_timeout", 30)

  def retain_releases(%__MODULE__{retain_releases: retain_releases})
      when is_integer(retain_releases),
      do: retain_releases

  def retain_releases(%__MODULE__{raw_config: raw}), do: Map.get(raw, "retain_releases", 5)

  def require_destination?(%__MODULE__{require_destination: require_destination})
      when is_boolean(require_destination),
      do: require_destination

  def require_destination?(%__MODULE__{raw_config: raw}),
    do: Map.get(raw, "require_destination", false)

  def primary_role_name(%__MODULE__{primary_role_name: primary_role_name})
      when is_binary(primary_role_name),
      do: primary_role_name

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

  @doc """
  Workspace on the `builder.remote` host where source is synced and the
  release is built. Per-service, so one build host can serve several apps.
  """
  def build_directory(%__MODULE__{} = config) do
    "#{run_directory()}/builds/#{service(config)}"
  end

  def audit_log_path(%__MODULE__{} = config) do
    "#{run_directory()}/#{service(config)}-audit.log"
  end

  # Private

  defp load_config_files(config_file, destination) do
    base = load_config_file(config_file)

    if destination do
      case destination_config_file(config_file, destination) do
        nil ->
          base

        dest_file ->
          dest_config = load_config_file(dest_file)
          deep_merge(base, dest_config)
      end
    else
      base
    end
  end

  defp destination_config_file(config_file, destination) do
    config_file
    |> destination_config_candidates(destination)
    |> Enum.find(&File.exists?/1)
  end

  defp destination_config_candidates(config_file, destination) do
    ext = Path.extname(config_file)
    root = Path.rootname(config_file)
    dirname = Path.dirname(config_file)
    basename = config_file |> Path.basename(ext) |> Path.rootname()

    [
      Path.join([dirname, basename, "#{destination}#{ext}"]),
      "#{root}.#{destination}#{ext}"
    ]
  end

  defp load_config_file(file) do
    unless File.exists?(file) do
      raise "Configuration file not found: #{file}"
    end

    file
    |> Config.Reader.read!()
    |> Keyword.get(:xamal, [])
    |> normalize_config()
  rescue
    e in Code.LoadError ->
      reraise RuntimeError,
              [message: "Failed to read #{file}: #{Exception.message(e)}"],
              __STACKTRACE__

    e in SyntaxError ->
      reraise RuntimeError,
              [message: "Failed to parse #{file}: #{Exception.message(e)}"],
              __STACKTRACE__
  end

  defp version_from_config(_raw_config) do
    System.get_env("VERSION") || Xamal.Utils.version_from_git()
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right

  defp normalize_config(config) when is_list(config) do
    if Keyword.keyword?(config) do
      Enum.into(config, %{}, fn {key, value} -> {normalize_key(key), normalize_config(value)} end)
    else
      Enum.map(config, &normalize_config/1)
    end
  end

  defp normalize_config(config) when is_map(config) do
    Map.new(config, fn {key, value} -> {normalize_key(key), normalize_config(value)} end)
  end

  defp normalize_config(value) when is_atom(value) and value not in [true, false, nil] do
    Atom.to_string(value)
  end

  defp normalize_config(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
