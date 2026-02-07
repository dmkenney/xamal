defmodule Xamal.Commands.Caddy do
  @moduledoc """
  Caddy install, config generation, reload, and management commands.
  """

  import Xamal.Commands.Base

  @doc """
  Install Caddy via apt on Debian/Ubuntu.
  """
  def install do
    combine([
      ["sudo", "apt-get", "install", "-y", "apt-transport-https", "curl"],
      pipe([
        ["curl", "-1sLf", "'https://dl.cloudsmith.io/public/caddy/stable/gpg.key'"],
        [
          "sudo",
          "gpg",
          "--batch",
          "--yes",
          "--dearmor",
          "-o",
          "/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
        ]
      ]),
      pipe([
        ["curl", "-1sLf", "'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt'"],
        ["sudo", "tee", "/etc/apt/sources.list.d/caddy-stable.list"]
      ]),
      ["sudo", "apt-get", "update"],
      ["sudo", "apt-get", "install", "-y", "caddy"]
    ])
  end

  @doc """
  Check if Caddy is installed.
  """
  def check_installed do
    ["caddy", "version"]
  end

  @doc """
  Write a Caddyfile to the service directory.
  """
  def write_caddyfile(config, upstream_port) do
    caddyfile_content = Xamal.Configuration.Caddy.generate_caddyfile(config.caddy, upstream_port)
    escaped = String.replace(caddyfile_content, "'", "'\\''")
    caddyfile_path = caddyfile_path(config)

    write([
      ["echo", "'#{escaped}'"],
      [caddyfile_path]
    ])
  end

  @doc """
  Write a maintenance mode Caddyfile.
  """
  def write_maintenance_caddyfile(config) do
    caddyfile_content = Xamal.Configuration.Caddy.maintenance_caddyfile(config.caddy)
    escaped = String.replace(caddyfile_content, "'", "'\\''")
    caddyfile_path = caddyfile_path(config)

    write([
      ["echo", "'#{escaped}'"],
      [caddyfile_path]
    ])
  end

  @doc """
  Replace /etc/caddy/Caddyfile with an import directive so Caddy picks up
  service Caddyfiles on reboot.
  """
  def configure_system_caddyfile do
    pipe([
      ["echo", "'import /opt/xamal/*/Caddyfile'"],
      ["sudo", "tee", "/etc/caddy/Caddyfile"]
    ])
  end

  @doc """
  Reload Caddy configuration (graceful - drains existing connections).
  """
  def reload(config) do
    ["sudo", "caddy", "reload", "--config", caddyfile_path(config)]
  end

  @doc """
  Start Caddy with the service Caddyfile.
  """
  def start(config) do
    ["caddy", "start", "--config", caddyfile_path(config)]
  end

  @doc """
  Stop Caddy.
  """
  def stop do
    ["caddy", "stop"]
  end

  @doc """
  Check Caddy status.
  """
  def status do
    ["systemctl", "is-active", "caddy"]
  end

  @doc """
  Read the active port from the active_port file.
  """
  def read_active_port(config) do
    ["cat", active_port_path(config)]
  end

  @doc """
  Write the active port to the active_port file.
  """
  def write_active_port(config, port) do
    write([
      ["echo", "#{port}"],
      [active_port_path(config)]
    ])
  end

  @doc """
  Get Caddy proxy logs via journalctl.
  Options: lines (default 100), since, grep, follow.
  """
  def logs(opts \\ []) do
    since = Keyword.get(opts, :since)
    lines = Keyword.get(opts, :lines, 100)
    grep = Keyword.get(opts, :grep)
    follow = Keyword.get(opts, :follow, false)

    cmd = ["journalctl", "-u", "caddy", "--no-pager"]
    cmd = if lines, do: cmd ++ ["-n", "#{lines}"], else: cmd
    cmd = if since, do: cmd ++ ["--since", Xamal.Utils.shell_escape(since)], else: cmd
    cmd = if follow, do: cmd ++ ["-f"], else: cmd

    if grep do
      pipe([cmd, ["grep", Xamal.Utils.shell_escape(grep)]])
    else
      cmd
    end
  end

  defp caddyfile_path(config) do
    "#{Xamal.Configuration.service_directory(config)}/Caddyfile"
  end

  defp active_port_path(config) do
    "#{Xamal.Configuration.service_directory(config)}/active_port"
  end
end
