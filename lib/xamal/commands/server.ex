defmodule Xamal.Commands.Server do
  @moduledoc """
  Server management commands: directory creation, bootstrap.
  """

  import Xamal.Commands.Base

  alias Xamal.Configuration

  @doc """
  Create all required directories on the server.
  """
  def bootstrap(config) do
    service_dir = Configuration.service_directory(config)
    user = config.ssh.user

    combine([
      ["sudo", "mkdir", "-p", service_dir],
      ["sudo", "chown", "#{user}:#{user}", service_dir],
      make_directory(Configuration.releases_directory(config)),
      make_directory("#{Configuration.env_directory(config)}/roles"),
      make_directory(Configuration.shared_directory(config)),
      make_directory(Configuration.run_directory()),
      write([["printf", "'#{Enum.join(ports(config), "\\n")}\\n'"], [ports_path(config)]])
    ])
  end

  @doc """
  Prints other services' `ports` files that claim either of this app's ports,
  and succeeds (exit 0) only if there are any.

  Each app records both of its blue-green ports at bootstrap. Systemd alone
  can't answer this: the idle port's instance is stopped and unloaded between
  deploys, so it doesn't show up, yet the next deploy will start it.
  """
  def claimed_port_conflicts(config) do
    base = Configuration.base_directory()

    pipe([
      ["grep", "-lxE", "'#{Enum.join(ports(config), "|")}'", "#{base}/*/ports", "2>/dev/null"],
      ["grep", "-vxF", ports_path(config)]
    ])
  end

  defp ports(config) do
    [config.caddy.app_port, Configuration.Caddy.alt_port(config.caddy)]
  end

  defp ports_path(config) do
    "#{Configuration.service_directory(config)}/ports"
  end

  @doc """
  Ensure the run directory exists (for locks, audit logs).
  """
  def ensure_run_directory do
    make_directory(Configuration.run_directory())
  end

  @doc """
  Remove the entire service directory.
  """
  def remove_service_directory(config) do
    remove_directory(Configuration.service_directory(config))
  end

  @doc """
  List the contents of the releases directory.
  """
  def list_releases(config) do
    ["ls", "-1", Configuration.releases_directory(config)]
  end

  @doc """
  Check the current symlink target.
  """
  def current_version(config) do
    ["readlink", "-f", Configuration.current_link(config)]
  end

  @doc """
  Create/update the current symlink to point to a release version.
  """
  def link_current(config, version) do
    release_path = "#{Configuration.releases_directory(config)}/#{version}"
    current = Configuration.current_link(config)

    ["ln", "-sfn", release_path, current]
  end
end
