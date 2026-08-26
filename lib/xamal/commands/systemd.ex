defmodule Xamal.Commands.Systemd do
  @moduledoc """
  Systemd service unit management commands.

  Uses template units (`<release>@.service`) with the port as instance identifier,
  enabling blue-green deploys (`myapp@4000` / `myapp@4001`), crash recovery via
  `Restart=on-failure`, and boot-time startup via `systemctl enable`.
  """

  import Xamal.Commands.Base

  alias Systemd.{UnitFile, UnitName}
  alias Xamal.Configuration
  alias Xamal.Configuration.{Caddy, Role}

  @unit_dir "/etc/systemd/system"

  @doc """
  Builds the parsed systemd unit file for a template service.
  """
  def unit_file(config) do
    release_name = config.release.name
    service_dir = Configuration.service_directory(config)
    user = config.ssh.user
    drain_timeout = Configuration.drain_timeout(config)

    unit_file =
      UnitFile.service(
        unit: [
          description: "#{release_name} (%i)",
          after: "network.target"
        ],
        service: [
          type: :exec,
          user: user,
          working_directory: "#{service_dir}/current",
          environment_file: "-#{service_dir}/env/app.env",
          environment: ["PORT=%i", "RELEASE_NODE=#{release_name}_%i"],
          exec_start: "#{service_dir}/current/bin/#{release_name} start",
          restart: "on-failure",
          restart_sec: 5,
          timeout_stop_sec: drain_timeout
        ],
        install: [wanted_by: "multi-user.target"]
      )

    :ok = UnitFile.validate(unit_file, :service)

    unit_file
  end

  @doc """
  Generate the systemd unit file content for a template service.
  """
  def generate_unit_content(config) do
    config
    |> unit_file()
    |> UnitFile.to_string()
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

  defp unit_path(config) do
    "#{@unit_dir}/#{config.release.name}@.service"
  end

  defp unit_instance(config, port) do
    UnitName.instance(config.release.name, port, :service)
  end
end
