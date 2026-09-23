defmodule Xamal.BuildTasks do
  @moduledoc """
  Release build and distribution task implementations.
  """

  import Xamal.Hooks
  import Xamal.Output

  alias Xamal.Commands.Base
  alias Xamal.Commands.Builder
  alias Xamal.Configuration
  alias Xamal.Configuration.Builder, as: BuildConfig
  alias Xamal.Context
  alias Xamal.SSH

  # deps.get + assets.deploy + mix release genuinely take minutes; SSH.execute
  # defaults to 30s, far too short here.
  @remote_build_timeout 600_000
  @remote_tarball_timeout 120_000

  def deliver(_args, opts, context) do
    skip_hooks = Keyword.get(opts, :skip_hooks, false)
    run_hook("pre-build", [skip_hooks: skip_hooks], context)
    build([], opts, context)
    run_hook("post-build", [skip_hooks: skip_hooks], context)
    upload([], opts, context)
  end

  def build(_args, _opts, context) do
    config = context.config

    cond do
      BuildConfig.docker?(config.builder) -> build_via_docker(config)
      BuildConfig.remote?(config.builder) -> build_via_remote(config)
      true -> build_locally(config)
    end
  end

  defp build_locally(config) do
    say("Building release locally...", :magenta)
    cmd_str = Base.to_command_string(Builder.build_release(config))

    case System.cmd("sh", ["-c", cmd_str], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        say("Release built successfully", :green)
        create_tarball_locally!(config)

      {_, code} ->
        raise "Build failed with exit code #{code}"
    end
  end

  defp build_via_docker(config) do
    verify_docker_available!()
    image = BuildConfig.docker_image(config.builder)
    say("Building release in Docker (#{image})...", :magenta)

    cmd_str = Base.to_command_string(Builder.build_in_docker(config))

    case System.cmd("sh", ["-c", cmd_str], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        say("Release built successfully", :green)
        create_tarball_locally!(config)

      {_, code} ->
        raise """
        Docker build failed with exit code #{code}.

        Image: #{image}

        This usually means:
          - The Docker image does not exist on the registry (check the tag)
          - Docker cannot pull the image (check network/auth)
          - The build commands failed inside the container

        To debug, try:
          docker pull #{image}
        """
    end
  end

  # Source is synced to the build host with `git archive HEAD | ssh ... tar -x`
  # (only committed files, which matches what the deploy dirty-check already
  # requires). That one step shells out to the real ssh binary because piping
  # local output into a remote command isn't something Erlang's :ssh can do.
  # `mix release` and the tarball then run there over the normal SSH.execute
  # path, and the tarball is fetched back to the same local path a local or
  # Docker build would have produced — so mix xamal.build.upload needs no
  # changes. When the build host is also a deploy host that costs a redundant
  # download-then-reupload, in exchange for one contract across every mode.
  defp build_via_remote(config) do
    destination = config.builder.remote
    {ssh_config, host} = remote_build_target(config)

    say("Building release on #{destination}...", :magenta)
    verify_remote_toolchain!(host, ssh_config, destination)

    say("  Syncing source to #{destination}...", :magenta)
    sync_source_to_remote!(config)

    say("  Running mix release on #{destination}...", :magenta)

    remote_exec!(
      host,
      Builder.build_release_remote(config),
      [ssh_config: ssh_config, timeout: @remote_build_timeout],
      "Remote build failed on #{destination}"
    )

    say("Release built successfully", :green)
    say("  Creating tarball on #{destination}...", :magenta)

    remote_exec!(
      host,
      Builder.create_tarball_remote(config),
      [ssh_config: ssh_config, timeout: @remote_tarball_timeout],
      "Failed to create tarball on #{destination}"
    )

    say("  Fetching tarball from #{destination}...", :magenta)
    fetch_tarball!(config, host, ssh_config, destination)

    say("Tarball created: #{Builder.tarball_path(config)}", :green)
  end

  # `builder.remote` may name a different user than the deploy hosts (a
  # dedicated build server), so ssh.user can't just be reused as-is.
  defp remote_build_target(config) do
    case String.split(config.builder.remote, "@", parts: 2) do
      [user, host] -> {%{config.ssh | user: user}, host}
      [host] -> {config.ssh, host}
    end
  end

  # A missing mix on the build host otherwise surfaces as "mix: command not
  # found" several minutes into what looks like a normal build.
  defp verify_remote_toolchain!(host, ssh_config, destination) do
    case SSH.execute(host, "command -v mix", ssh_config: ssh_config) do
      {:ok, _} ->
        :ok

      {:error, {:exit_status, _, _}} ->
        raise """
        Cannot use build host #{destination}: mix not found.

        The build host needs Elixir and OTP installed, at versions matching \
        what the target servers expect. If Elixir is installed via a version \
        manager (asdf, mise, kerl), make sure it is on the PATH for \
        non-interactive SSH sessions — ~/.bashrc is not sourced for those.
        """

      {:error, reason} ->
        raise "Cannot connect to build host #{destination}: #{inspect(reason)}"
    end
  end

  defp remote_exec!(host, command, opts, error_message) do
    case SSH.execute_command(host, command, opts) do
      {:ok, output} ->
        output

      {:error, reason} ->
        raise "#{error_message}: #{inspect(reason)}"
    end
  end

  defp sync_source_to_remote!(config) do
    destination = config.builder.remote
    dir = Configuration.build_directory(config)
    flags = config.ssh |> SSH.ssh_flags(config.ssh.port) |> Enum.join(" ")
    remote_setup = "mkdir -p #{dir} && tar -x -C #{dir}"
    pipeline = "git archive --format=tar HEAD | ssh #{flags} #{destination} '#{remote_setup}'"

    case System.cmd("sh", ["-c", pipeline], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, code} ->
        raise "Failed to sync source to build host #{destination} (exit #{code}):\n#{output}"
    end
  end

  defp fetch_tarball!(config, host, ssh_config, destination) do
    remote_path = Builder.remote_tarball_path(config)
    local_path = Builder.tarball_path(config)

    case SSH.download(host, remote_path, local_path, ssh_config: ssh_config) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise "Failed to fetch tarball from #{destination}: #{inspect(reason)}"
    end
  end

  defp create_tarball_locally!(config) do
    say("Creating tarball...", :magenta)
    tarball_str = Base.to_command_string(Builder.create_tarball(config))

    case System.cmd("sh", ["-c", tarball_str], stderr_to_stdout: true) do
      {_, 0} -> say("Tarball created: #{Builder.tarball_path(config)}", :green)
      {output, _} -> raise "Failed to create tarball: #{output}"
    end
  end

  defp verify_docker_available! do
    case System.cmd("docker", ["info"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {_, _} ->
        raise """
        Docker is not available.

        The builder is configured to use Docker but the 'docker' command is not \
        working. Make sure Docker is installed and running.
        """
    end
  rescue
    e in ErlangError ->
      reraise RuntimeError,
              [
                message: """
                Docker is not installed.

                The builder is configured to use Docker but the 'docker' command was not \
                found. Install Docker to use Docker-based builds, or remove the 'docker' \
                setting from your builder configuration.

                Original error: #{inspect(e)}
                """
              ],
              __STACKTRACE__
  end

  def upload(_args, _opts, context) do
    config = context.config
    hosts = Context.hosts(context)

    tarball_path = Builder.tarball_path(config)

    unless File.exists?(tarball_path) do
      raise "Tarball not found at #{tarball_path}. Run 'mix xamal.build' first."
    end

    Enum.each(hosts, fn host ->
      say("  Uploading to #{host}...", :magenta)

      version = config.version
      remote_dir = "#{Configuration.releases_directory(config)}/#{version}"

      # Create remote directory
      mkdir_cmd = Base.make_directory(remote_dir)
      SSH.execute_command(host, mkdir_cmd, ssh_config: config.ssh)

      # Upload via SFTP (works with key_data)
      remote_path = "#{remote_dir}/#{Builder.tarball_name(config)}"

      case SSH.upload(host, tarball_path, remote_path, ssh_config: config.ssh) do
        {:ok, _} ->
          # Unpack on remote
          unpack_cmd = Builder.unpack_tarball(config)
          SSH.execute_command(host, unpack_cmd, ssh_config: config.ssh)
          say("  Deployed to #{host}", :green)

        {:error, reason} ->
          raise "Failed to upload to #{host}: #{inspect(reason)}"
      end
    end)
  end

  def details(_args, _opts, context) do
    config = context.config

    IO.puts("Build configuration:")
    IO.puts("  Release name: #{config.release.name}")
    IO.puts("  Mix env: #{config.release.mix_env}")
    IO.puts("  Version: #{config.version}")
    IO.puts("  Builder: #{builder_type(config.builder)}")
    IO.puts("  Tarball: #{Builder.tarball_path(config)}")
  end

  defp builder_type(builder) do
    cond do
      BuildConfig.docker?(builder) -> "docker"
      BuildConfig.remote?(builder) -> "remote (#{builder.remote})"
      true -> "local"
    end
  end
end
