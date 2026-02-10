defmodule Xamal.CLI.Build do
  @moduledoc """
  CLI commands for building and distributing releases.
  """

  import Xamal.CLI.Base

  def run(subcommand, args, opts) do
    case subcommand do
      "deliver" -> deliver(args, opts)
      "push" -> push(args, opts)
      "pull" -> pull(args, opts)
      "details" -> details(args, opts)
      other -> say("Unknown build command: #{other}", :red)
    end
  end

  def deliver(_args, opts) do
    run_hook("pre-build", skip_hooks: Keyword.get(opts, :skip_hooks, false))
    push([], opts)
    pull([], opts)
  end

  def push(_args, _opts) do
    config = Xamal.Commander.config()
    docker? = Xamal.Configuration.Builder.docker?(config.builder)

    if docker? do
      verify_docker_available!()
      image = Xamal.Configuration.Builder.docker_image(config.builder)
      say("Building release in Docker (#{image})...", :magenta)
    else
      say("Building release locally...", :magenta)
    end

    build_cmd =
      if docker? do
        Xamal.Commands.Builder.build_in_docker(config)
      else
        Xamal.Commands.Builder.build_release(config)
      end

    cmd_str = Xamal.Commands.Base.to_command_string(build_cmd)

    case System.cmd("sh", ["-c", cmd_str], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        say("Release built successfully", :green)

        say("Creating tarball...", :magenta)
        tarball_cmd = Xamal.Commands.Builder.create_tarball(config)
        tarball_str = Xamal.Commands.Base.to_command_string(tarball_cmd)

        case System.cmd("sh", ["-c", tarball_str], stderr_to_stdout: true) do
          {_, 0} -> say("Tarball created: #{Xamal.Commands.Builder.tarball_path(config)}", :green)
          {output, _} -> raise "Failed to create tarball: #{output}"
        end

      {_, code} when docker? ->
        image = Xamal.Configuration.Builder.docker_image(config.builder)

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
      raise """
      Docker is not installed.

      The builder is configured to use Docker but the 'docker' command was not \
      found. Install Docker to use Docker-based builds, or remove the 'docker' \
      setting from your builder configuration.

      Original error: #{inspect(e)}
      """
  end

  def pull(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    tarball_path = Xamal.Commands.Builder.tarball_path(config)

    unless File.exists?(tarball_path) do
      raise "Tarball not found at #{tarball_path}. Run 'xamal build push' first."
    end

    Enum.each(hosts, fn host ->
      say("  Uploading to #{host}...", :magenta)

      version = config.version
      remote_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"

      # Create remote directory
      mkdir_cmd = Xamal.Commands.Base.make_directory(remote_dir)
      Xamal.SSH.execute_command(host, mkdir_cmd, ssh_config: config.ssh)

      # Upload via SFTP (works with key_data)
      remote_path = "#{remote_dir}/#{Xamal.Commands.Builder.tarball_name(config)}"

      case Xamal.SSH.upload(host, tarball_path, remote_path, ssh_config: config.ssh) do
        {:ok, _} ->
          # Unpack on remote
          unpack_cmd = Xamal.Commands.Builder.unpack_tarball(config)
          Xamal.SSH.execute_command(host, unpack_cmd, ssh_config: config.ssh)
          say("  Deployed to #{host}", :green)

        {:error, reason} ->
          raise "Failed to upload to #{host}: #{inspect(reason)}"
      end
    end)
  end

  def details(_args, _opts) do
    config = Xamal.Commander.config()

    IO.puts("Build configuration:")
    IO.puts("  Release name: #{config.release.name}")
    IO.puts("  Mix env: #{config.release.mix_env}")
    IO.puts("  Version: #{config.version}")
    IO.puts("  Builder: #{builder_type(config.builder)}")
    IO.puts("  Tarball: #{Xamal.Commands.Builder.tarball_path(config)}")
  end

  def help do
    IO.puts("""
    Usage: xamal build <command>

    Commands:
      deliver    Build release locally and distribute to servers
      push       Build release locally
      pull       Upload tarball to servers
      details    Show build configuration
    """)
  end

  defp builder_type(builder) do
    cond do
      Xamal.Configuration.Builder.docker?(builder) -> "docker"
      Xamal.Configuration.Builder.remote?(builder) -> "remote (#{builder.remote})"
      true -> "local"
    end
  end
end
