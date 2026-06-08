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

  def deliver(_args, opts, context) do
    skip_hooks = Keyword.get(opts, :skip_hooks, false)
    run_hook("pre-build", [skip_hooks: skip_hooks], context)
    build([], opts, context)
    run_hook("post-build", [skip_hooks: skip_hooks], context)
    upload([], opts, context)
  end

  def build(_args, _opts, context) do
    config = context.config
    docker? = BuildConfig.docker?(config.builder)

    if docker? do
      verify_docker_available!()
      image = BuildConfig.docker_image(config.builder)
      say("Building release in Docker (#{image})...", :magenta)
    else
      say("Building release locally...", :magenta)
    end

    build_cmd =
      if docker? do
        Builder.build_in_docker(config)
      else
        Builder.build_release(config)
      end

    cmd_str = Base.to_command_string(build_cmd)

    case System.cmd("sh", ["-c", cmd_str], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        say("Release built successfully", :green)

        say("Creating tarball...", :magenta)
        tarball_cmd = Builder.create_tarball(config)
        tarball_str = Base.to_command_string(tarball_cmd)

        case System.cmd("sh", ["-c", tarball_str], stderr_to_stdout: true) do
          {_, 0} -> say("Tarball created: #{Builder.tarball_path(config)}", :green)
          {output, _} -> raise "Failed to create tarball: #{output}"
        end

      {_, code} when docker? ->
        image = BuildConfig.docker_image(config.builder)

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

      {_, code} ->
        raise "Build failed with exit code #{code}"
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
