defmodule Xamal.Commands.Systemd do
  @moduledoc """
  Systemd service unit management commands.

  Uses template units (`<release>@.service`) with the port as instance identifier,
  enabling blue-green deploys (`myapp@4000` / `myapp@4001`), crash recovery via
  `Restart=on-failure`, and boot-time startup via `systemctl enable`.
  """

  import Xamal.Commands.Base

  alias Xamal.Configuration
  alias Xamal.Configuration.{Caddy, Role}

  @unit_dir "/etc/systemd/system"

  @doc """
  Generate the systemd unit file content for a template service.
  """
  def generate_unit_content(config) do
    release_name = config.release.name
    service_dir = Configuration.service_directory(config)
    user = config.ssh.user
    drain_timeout = Configuration.drain_timeout(config)

    """
    [Unit]
    Description=#{release_name} (%i)
    After=network.target

    [Service]
    Type=exec
    User=#{user}
    WorkingDirectory=#{service_dir}/current
    EnvironmentFile=-#{service_dir}/env/app.env
    Environment=PORT=%i
    Environment=RELEASE_NODE=#{release_name}_%i
    ExecStart=#{service_dir}/current/bin/#{release_name} start
    Restart=on-failure
    RestartSec=5
    TimeoutStopSec=#{drain_timeout}

    [Install]
    WantedBy=multi-user.target
    """
  end

  @doc """
  Write the template unit file and reload systemd.
  """
  def install_unit(config) do
    content = generate_unit_content(config)
    escaped = String.replace(content, "'", "'\\''")
    path = unit_path(config)

    combine([
      pipe([
        ["echo", "'#{escaped}'"],
        ["sudo", "tee", path]
      ]),
      ["sudo", "systemctl", "daemon-reload"]
    ])
  end

  @doc """
  Write the template unit only if its content changed, then reload systemd.

  Prints `unit-updated` when it replaced the file, so the caller can say
  so. `daemon-reload` re-reads unit definitions without restarting running
  services, so the serving instance keeps running and the new definition
  applies from the next `systemctl start`.
  """
  def sync_unit(config) do
    content = generate_unit_content(config)
    escaped = String.replace(content, "'", "'\\''")
    path = unit_path(config)
    staged = "#{path}.xamal-new"

    shell([
      "echo '#{escaped}' | sudo tee #{staged} >/dev/null &&",
      "if cmp -s #{staged} #{path}; then sudo rm -f #{staged};",
      "else sudo mv #{staged} #{path} && sudo systemctl daemon-reload && echo unit-updated; fi"
    ])
  end

  @doc """
  Prints other template units that run this service (their `WorkingDirectory`
  is this service's) under a different name, and succeeds (exit 0) only if
  there are any. That's what a `release.name` change leaves behind.
  """
  def units_under_other_names(config) do
    working_dir = "WorkingDirectory=#{Configuration.service_directory(config)}/current"

    pipe([
      ["grep", "-lxF", "'#{working_dir}'", "#{@unit_dir}/*@.service", "2>/dev/null"],
      ["grep", "-vxF", unit_path(config)]
    ])
  end

  @doc """
  Start a service instance on the given port.
  """
  def start(config, port) do
    ["sudo", "systemctl", "start", unit_instance(config, port)]
  end

  @doc """
  Stop a service instance on the given port.
  """
  def stop(config, port) do
    ["sudo", "systemctl", "stop", unit_instance(config, port)]
  end

  @doc """
  Enable a service instance for boot-time startup.
  """
  def enable(config, port) do
    ["sudo", "systemctl", "enable", unit_instance(config, port)]
  end

  @doc """
  Disable a service instance from boot-time startup.
  """
  def disable(config, port) do
    ["sudo", "systemctl", "disable", unit_instance(config, port)]
  end

  @doc """
  Stop both port instances (tolerates failures via chain).
  """
  def stop_all(config) do
    app_port = config.caddy.app_port
    alt_port = Caddy.alt_port(config.caddy)

    chain([
      stop(config, app_port),
      stop(config, alt_port)
    ])
  end

  @doc """
  Disable both port instances from boot-time startup.
  """
  def disable_all(config) do
    app_port = config.caddy.app_port
    alt_port = Caddy.alt_port(config.caddy)

    chain([
      disable(config, app_port),
      disable(config, alt_port)
    ])
  end

  @doc """
  Remove the unit file and reload systemd.
  """
  def remove_unit(config) do
    combine([
      ["sudo", "rm", "-f", unit_path(config)],
      ["sudo", "systemctl", "daemon-reload"]
    ])
  end

  @doc """
  Create a symlink from env/app.env to the role-specific env file.
  """
  def write_env_symlink(config, role) do
    role_env = Role.secrets_path(role, config)
    app_env = "#{Configuration.env_directory(config)}/app.env"

    ["ln", "-sfn", role_env, app_env]
  end

  @doc """
  Succeeds (exit 0) when the template unit for this release name already
  exists but belongs to a different service directory — i.e. another app on
  the host uses the same release name, and installing ours would overwrite it.
  """
  def unit_owned_by_other_service(config) do
    path = unit_path(config)
    working_dir = "WorkingDirectory=#{Configuration.service_directory(config)}/current"

    combine([
      ["test", "-f", path],
      ["!", "grep", "-qxF", "'#{working_dir}'", path]
    ])
  end

  @doc """
  Prints the systemd instances bound to this app's ports that belong to a
  different release, and succeeds (exit 0) only if there are any.
  """
  def port_conflicts(config) do
    ports = [config.caddy.app_port, Caddy.alt_port(config.caddy)]
    patterns = Enum.map(ports, &"'*@#{&1}.service'")
    own = Enum.flat_map(ports, &["-e", "#{unit_instance(config, &1)}.service"])

    pipe([
      ["systemctl", "list-units", "--all", "--plain", "--no-legend" | patterns],
      ["awk", "'{print $1}'"],
      ["grep", "-vxF" | own]
    ])
  end

  defp unit_path(config) do
    "#{@unit_dir}/#{config.release.name}@.service"
  end

  defp unit_instance(config, port) do
    "#{config.release.name}@#{port}"
  end
end
