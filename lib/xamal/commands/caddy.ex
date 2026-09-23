defmodule Xamal.Commands.Caddy do
  @moduledoc """
  Caddy install, config generation, reload, and management commands.
  """

  import Xamal.Commands.Base

  alias Xamal.Configuration
  alias Xamal.Configuration.Caddy, as: CaddyConfig

  @system_caddyfile "/etc/caddy/Caddyfile"
  @import_line "import /opt/xamal/*/Caddyfile"

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
      ["sudo", "apt-get", "install", "-y", "caddy"],
      # The package ships a :80 welcome site. Caddy was just installed, so
      # nothing else is in the file yet; replace it with the import line.
      pipe([
        ["echo", "'#{@import_line}'"],
        ["sudo", "tee", @system_caddyfile]
      ])
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
    caddyfile_content = CaddyConfig.generate_caddyfile(config.caddy, upstream_port)
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
    caddyfile_content = CaddyConfig.maintenance_caddyfile(config.caddy)
    escaped = String.replace(caddyfile_content, "'", "'\\''")
    caddyfile_path = caddyfile_path(config)

    write([
      ["echo", "'#{escaped}'"],
      [caddyfile_path]
    ])
  end

  @doc """
  The host-wide Caddyfile. It imports every service's Caddyfile, which is what
  lets several apps share one Caddy.
  """
  def system_caddyfile_path, do: @system_caddyfile

  @doc """
  Ensure the system Caddyfile imports the service Caddyfiles, so Caddy loads
  every app on reload and after a reboot.

  Appends the import line only if it is missing, and leaves everything else in
  the file alone (global options, sites managed outside Xamal). If the file's
  last line has no trailing newline, one is added first so the import line
  isn't glued onto it.
  """
  def configure_system_caddyfile do
    ["sudo" | shell([import_ensure_script(@system_caddyfile)])]
  end

  @doc false
  def import_ensure_script(path) do
    """
    grep -qxF '#{@import_line}' #{path} 2>/dev/null || {
      if [ -s #{path} ] && [ -n "$(tail -c1 #{path})" ]; then printf '\\n' >> #{path}; fi
      printf '%s\\n' '#{@import_line}' >> #{path}
    }
    """
  end

  @doc """
  Make sure the Caddy service is enabled and running, since `reload/0` talks
  to the running instance.
  """
  def enable do
    ["sudo", "systemctl", "enable", "--now", "caddy"]
  end

  @doc """
  Reload Caddy from the system Caddyfile (graceful - drains existing
  connections).

  `caddy reload --config <file>` replaces the entire running config with what
  that file resolves to. Reloading from a service's own Caddyfile would drop
  every other app on the host, so this always reloads the system file, which
  imports them all. Caddy validates the whole config first and leaves the
  running config untouched if it is invalid.
  """
  def reload do
    ["sudo", "caddy", "reload", "--config", @system_caddyfile]
  end

  @doc """
  Start Caddy with the system Caddyfile (see `reload/0` for why not the
  service one).
  """
  def start do
    ["caddy", "start", "--config", @system_caddyfile]
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

  @doc """
  Prints other services' Caddyfiles that already use the `:80` catch-all site
  (what an app with no `caddy.host` gets), and succeeds (exit 0) only if there
  are any. Two catch-alls in the imported set make every Caddy reload fail.
  """
  def catch_all_conflicts(config) do
    pipe([
      ["grep", "-lx", "':80 {'", "#{Configuration.base_directory()}/*/Caddyfile", "2>/dev/null"],
      ["grep", "-vxF", caddyfile_path(config)]
    ])
  end

  defp caddyfile_path(config) do
    "#{Configuration.service_directory(config)}/Caddyfile"
  end

  defp active_port_path(config) do
    "#{Configuration.service_directory(config)}/active_port"
  end
end
