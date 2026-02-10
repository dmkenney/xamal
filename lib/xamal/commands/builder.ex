defmodule Xamal.Commands.Builder do
  @moduledoc """
  Build commands: mix release, tarball creation, SCP distribution.
  """

  import Xamal.Commands.Base

  @doc """
  Build the release locally with mix release.
  """
  def build_release(config) do
    release_name = config.release.name
    mix_env = config.release.mix_env

    combine([
      ["MIX_ENV=#{mix_env}", "mix", "deps.get", "--only", mix_env],
      ["MIX_ENV=#{mix_env}", "mix", "assets.deploy"],
      ["MIX_ENV=#{mix_env}", "mix", "release", release_name, "--overwrite"]
    ])
  end

  @doc """
  Create a tarball from the built release.
  """
  def create_tarball(config) do
    release_name = config.release.name
    mix_env = config.release.mix_env
    tarball = tarball_path(config)
    release_dir = "_build/#{mix_env}/rel/#{release_name}"

    ["tar", "-czf", tarball, "-C", release_dir, "."]
  end

  @doc """
  Upload the tarball to a remote host and unpack it.
  """
  def deploy_to_host(config) do
    version = config.version
    release_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"

    combine([
      make_directory(release_dir),
      ["tar", "-xzf", "-", "-C", release_dir]
    ])
  end

  @doc """
  Upload the env file for a role to the remote host.
  """
  def upload_env_file(config, role) do
    env_path = Xamal.Configuration.Role.secrets_path(role, config)

    make_directory(Path.dirname(env_path))
  end

  @doc """
  The tarball filename.
  """
  def tarball_name(config) do
    "#{config.release.name}-#{config.version}.tar.gz"
  end

  @doc """
  The local tarball path.
  """
  def tarball_path(config) do
    mix_env = config.release.mix_env
    "_build/#{mix_env}/#{tarball_name(config)}"
  end

  @doc """
  Build the release inside a Docker container for cross-compilation.

  The Docker image can be configured via `builder.docker` in deploy.yml:
  - `docker: true` uses a default hexpm/elixir image
  - `docker: "image:tag"` uses the specified image

  Builder args from `builder.args` are passed as environment variables via `-e` flags.
  """
  def build_in_docker(config) do
    image = Xamal.Configuration.Builder.docker_image(config.builder)
    release_name = config.release.name
    mix_env = config.release.mix_env

    env_flags =
      (config.builder.args || %{})
      |> Enum.flat_map(fn {k, v} -> ["-e", "#{k}=#{v}"] end)

    volume_flags =
      (config.builder.volumes || [])
      |> Enum.flat_map(fn vol -> ["-v", vol] end)

    # Use host UID/GID so build artifacts aren't owned by root
    build_steps =
      [
        "command -v git >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq git build-essential >/dev/null 2>&1)",
        "mix local.hex --if-missing --force",
        "mix local.rebar --if-missing --force",
        "MIX_ENV=#{mix_env} mix deps.get --only #{mix_env}",
        "MIX_ENV=#{mix_env} mix deps.compile",
        "mix tailwind.install --if-missing",
        "mix esbuild.install --if-missing",
        "MIX_ENV=#{mix_env} mix assets.deploy",
        "MIX_ENV=#{mix_env} mix release #{release_name} --overwrite",
        "chown -R $(stat -c '%u:%g' /app) /app/_build /app/deps /app/priv/static"
      ]
      |> Enum.join(" && ")

    combine([
      ["docker", "run", "--rm", "-v", "$(pwd):/app", "-w", "/app"] ++
        volume_flags ++
        env_flags ++
        [image, "sh", "-c", "'#{build_steps}'"]
    ])
  end

  @doc """
  SCP command to upload tarball to a host.
  """
  def scp_tarball(config, host, ssh_config) do
    local_tarball = tarball_path(config)
    version = config.version
    remote_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"
    remote_path = "#{remote_dir}/#{tarball_name(config)}"

    port_arg = if ssh_config.port != 22, do: "-P #{ssh_config.port}", else: ""

    "scp #{port_arg} #{local_tarball} #{ssh_config.user}@#{host}:#{remote_path}"
  end

  @doc """
  Unpack the tarball on the remote host.
  """
  def unpack_tarball(config) do
    version = config.version
    release_dir = "#{Xamal.Configuration.releases_directory(config)}/#{version}"
    tarball = "#{release_dir}/#{tarball_name(config)}"

    combine([
      ["tar", "-xzf", tarball, "-C", release_dir],
      remove_file(tarball)
    ])
  end
end
