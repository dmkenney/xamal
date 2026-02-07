defmodule Xamal.Commands.Server do
  @moduledoc """
  Server management commands: directory creation, bootstrap.
  """

  import Xamal.Commands.Base

  @doc """
  Create all required directories on the server.
  """
  def bootstrap(config) do
    service_dir = Xamal.Configuration.service_directory(config)
    user = config.ssh.user

    combine([
      ["sudo", "mkdir", "-p", service_dir],
      ["sudo", "chown", "#{user}:#{user}", service_dir],
      make_directory(Xamal.Configuration.releases_directory(config)),
      make_directory("#{Xamal.Configuration.env_directory(config)}/roles"),
      make_directory(Xamal.Configuration.shared_directory(config)),
      make_directory(Xamal.Configuration.run_directory())
    ])
  end

  @doc """
  Ensure the run directory exists (for locks, audit logs).
  """
  def ensure_run_directory do
    make_directory(Xamal.Configuration.run_directory())
  end

  @doc """
  Remove the entire service directory.
  """
  def remove_service_directory(config) do
    remove_directory(Xamal.Configuration.service_directory(config))
  end

  @doc """
  List the contents of the releases directory.
  """
  def list_releases(config) do
    ["ls", "-1", Xamal.Configuration.releases_directory(config)]
  end

  @doc """
  Check the current symlink target.
  """
  def current_version(config) do
    ["readlink", "-f", Xamal.Configuration.current_link(config)]
  end

  @doc """
  Create/update the current symlink to point to a release version.
  """
  def link_current(config, version) do
    release_path = "#{Xamal.Configuration.releases_directory(config)}/#{version}"
    current = Xamal.Configuration.current_link(config)

    ["ln", "-sfn", release_path, current]
  end
end
