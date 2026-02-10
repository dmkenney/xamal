defmodule Xamal.Commands.App do
  @moduledoc """
  Release lifecycle commands: start, stop, status, version, exec, logs.
  """

  import Xamal.Commands.Base

  @doc """
  Start the release as a daemon on a given port.

  Sources the role env file, sets PORT, then runs `bin/<app> daemon`.
  """
  def start(config, role, port) do
    bin = release_bin(config)
    env_file = Xamal.Configuration.Role.secrets_path(role, config)
    service_dir = Xamal.Configuration.service_directory(config)
    release_name = config.release.name

    combine([
      ["set", "-a"],
      [".", env_file],
      ["set", "+a"],
      ["cd", "#{service_dir}/current"],
      ["PORT=#{port}", "RELEASE_NODE=#{release_name}_#{port}", bin, "daemon"]
    ])
  end

  @doc """
  Start a specific release version on a given port.
  """
  def start_version(config, role, version, port) do
    bin = release_bin(config)
    env_file = Xamal.Configuration.Role.secrets_path(role, config)
    release_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"
    release_name = config.release.name

    combine([
      ["set", "-a"],
      [".", env_file],
      ["set", "+a"],
      ["cd", release_dir],
      ["PORT=#{port}", "RELEASE_NODE=#{release_name}_#{port}", bin, "daemon"]
    ])
  end

  @doc """
  Stop the running release.
  """
  def stop(config, port \\ nil) do
    bin = release_bin(config)
    current = Xamal.Configuration.current_link(config)

    if port do
      release_name = config.release.name
      ["RELEASE_NODE=#{release_name}_#{port}", "#{current}/#{bin}", "stop"]
    else
      ["#{current}/#{bin}", "stop"]
    end
  end

  @doc """
  Stop a specific release version.
  """
  def stop_version(config, version, port \\ nil) do
    bin = release_bin(config)
    release_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"

    if port do
      release_name = config.release.name
      ["RELEASE_NODE=#{release_name}_#{port}", "#{release_dir}/#{bin}", "stop"]
    else
      ["#{release_dir}/#{bin}", "stop"]
    end
  end

  @doc """
  Check if the release is running (pid check).
  """
  def running?(config, port \\ nil) do
    bin = release_bin(config)
    current = Xamal.Configuration.current_link(config)

    if port do
      release_name = config.release.name
      ["RELEASE_NODE=#{release_name}_#{port}", "#{current}/#{bin}", "pid"]
    else
      ["#{current}/#{bin}", "pid"]
    end
  end

  @doc """
  Get the running release version by reading the current symlink.
  """
  def current_version(config) do
    pipe([
      ["readlink", "-f", Xamal.Configuration.current_link(config)],
      ["xargs", "basename"]
    ])
  end

  @doc """
  Execute a command in the context of the running release.

  Uses `bin/<app> rpc` for non-interactive, `bin/<app> remote` for interactive.
  """
  def exec(config, command, opts \\ []) do
    interactive = Keyword.get(opts, :interactive, false)
    port = Keyword.get(opts, :port)
    bin = release_bin(config)
    current = Xamal.Configuration.current_link(config)
    env_file = "#{Xamal.Configuration.env_directory(config)}/app.env"

    # Source the env file so runtime.exs has the required env vars,
    # and set RELEASE_NODE so we connect to the correct node.
    env_prefix =
      ["set -a", ". #{env_file}", "set +a"] ++
        if(port, do: ["export RELEASE_NODE=#{config.release.name}_#{port}"], else: [])

    shell_prefix = Enum.join(env_prefix, " && ")

    if interactive do
      ["#{shell_prefix} &&", "#{current}/#{bin}", "remote"]
    else
      escaped = String.replace(command, "'", "'\\''")
      ["#{shell_prefix} &&", "#{current}/#{bin}", "rpc", "'#{escaped}'"]
    end
  end

  @doc """
  Execute an arbitrary command within the release environment.
  """
  def eval(config, expression) do
    bin = release_bin(config)
    current = Xamal.Configuration.current_link(config)

    ["#{current}/#{bin}", "eval", Xamal.Utils.shell_escape(expression)]
  end

  @doc """
  Get logs via journalctl for the release service.
  Uses systemd journal since we run as a daemon.
  """
  def logs(config, opts \\ []) do
    since = Keyword.get(opts, :since)
    lines = Keyword.get(opts, :lines, 100)
    grep = Keyword.get(opts, :grep)
    follow = Keyword.get(opts, :follow, false)
    port = Keyword.get(opts, :port)

    release_name = config.release.name

    unit =
      if port do
        "#{release_name}@#{port}"
      else
        "#{release_name}@*"
      end

    cmd = ["journalctl", "-u", unit, "--no-pager"]
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
  List all release directories.
  """
  def list_releases(config) do
    ["ls", "-1t", Xamal.Configuration.releases_directory(config)]
  end

  @doc """
  List stale (non-current) releases.
  """
  def stale_releases(config, keep) do
    pipe([
      list_releases(config),
      ["tail", "-n", "+#{keep + 1}"]
    ])
  end

  @doc """
  Remove a specific release directory.
  """
  def remove_release(config, version) do
    release_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"
    remove_directory(release_dir)
  end

  @doc """
  Show details about the running release.
  """
  def details(config, port \\ nil) do
    bin = release_bin(config)
    current = Xamal.Configuration.current_link(config)

    node_env =
      if port do
        "RELEASE_NODE=#{config.release.name}_#{port}"
      end

    version_cmd = [node_env, "#{current}/#{bin}", "version"] |> Enum.reject(&is_nil/1)
    pid_cmd = [node_env, "#{current}/#{bin}", "pid"] |> Enum.reject(&is_nil/1)

    chain([
      ["echo", "'Current release:'"],
      ["readlink", "-f", current],
      ["echo", "'Release version:'"],
      version_cmd,
      ["echo", "'PID:'"],
      pid_cmd
    ])
  end

  defp release_bin(config) do
    Xamal.Configuration.Release.bin_path(config.release)
  end
end
