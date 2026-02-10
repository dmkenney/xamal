defmodule Xamal.Commands.Systemd do
  @moduledoc """
  Systemd service unit management commands.

  Uses template units (`<release>@.service`) with the port as instance identifier,
  enabling blue-green deploys (`myapp@4000` / `myapp@4001`), crash recovery via
  `Restart=on-failure`, and boot-time startup via `systemctl enable`.
  """

  import Xamal.Commands.Base

  @unit_dir "/etc/systemd/system"

  @doc """
  Generate the systemd unit file content for a template service.
  """
  def generate_unit_content(config) do
    release_name = config.release.name
    service_dir = Xamal.Configuration.service_directory(config)
    user = config.ssh.user
    drain_timeout = Xamal.Configuration.drain_timeout(config)

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
    alt_port = Xamal.Configuration.Caddy.alt_port(config.caddy)

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
    alt_port = Xamal.Configuration.Caddy.alt_port(config.caddy)

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
    role_env = Xamal.Configuration.Role.secrets_path(role, config)
    app_env = "#{Xamal.Configuration.env_directory(config)}/app.env"

    ["ln", "-sfn", role_env, app_env]
  end

  defp unit_path(config) do
    "#{@unit_dir}/#{config.release.name}@.service"
  end

  defp unit_instance(config, port) do
    "#{config.release.name}@#{port}"
  end
end
