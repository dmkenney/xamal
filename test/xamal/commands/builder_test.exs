defmodule Xamal.Commands.BuilderTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Builder

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    version: "abc1234",
    roles: [],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{},
    aliases: %{}
  }

  describe "build_release/1" do
    test "builds mix release command" do
      cmd = Builder.build_release(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "MIX_ENV=prod"
      assert cmd_str =~ "mix deps.get"
      assert cmd_str =~ "mix release my_app"
      assert cmd_str =~ "--overwrite"
    end
  end

  describe "create_tarball/1" do
    test "builds tar command" do
      cmd = Builder.create_tarball(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "tar"
      assert cmd_str =~ "-czf"
      assert cmd_str =~ "my_app-abc1234.tar.gz"
      assert cmd_str =~ "_build/prod/rel/my_app"
    end
  end

  describe "deploy_to_host/1" do
    test "creates release directory and unpacks" do
      cmd = Builder.deploy_to_host(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "mkdir -p"
      assert cmd_str =~ "/opt/xamal/my-app/releases/abc1234"
      assert cmd_str =~ "tar -xzf"
    end
  end

  describe "tarball_name/1" do
    test "returns tarball filename" do
      assert Builder.tarball_name(@config) == "my_app-abc1234.tar.gz"
    end
  end

  describe "tarball_path/1" do
    test "returns local tarball path" do
      assert Builder.tarball_path(@config) == "_build/prod/my_app-abc1234.tar.gz"
    end
  end

  describe "build_in_docker/1" do
    test "builds docker run command with default image" do
      cmd = Builder.build_in_docker(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "docker run --rm"
      assert cmd_str =~ "-v $(pwd):/app"
      assert cmd_str =~ "-w /app"
      assert cmd_str =~ "hexpm/elixir"
      assert cmd_str =~ "sh -c"
    end

    test "uses custom image when docker is a string" do
      config = put_in(@config.builder, %Xamal.Configuration.Builder{docker: "my-org/elixir:1.18"})
      cmd = Builder.build_in_docker(config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "my-org/elixir:1.18"
      refute cmd_str =~ "hexpm/elixir"
    end

    test "includes build steps" do
      cmd = Builder.build_in_docker(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "apt-get update"
      assert cmd_str =~ "mix local.hex --force"
      assert cmd_str =~ "mix local.rebar --force"
      assert cmd_str =~ "MIX_ENV=prod mix deps.get --only prod"
      assert cmd_str =~ "MIX_ENV=prod mix deps.compile"
      assert cmd_str =~ "mix tailwind.install --if-missing"
      assert cmd_str =~ "mix esbuild.install --if-missing"
      assert cmd_str =~ "MIX_ENV=prod mix assets.deploy"
      assert cmd_str =~ "MIX_ENV=prod mix release my_app --overwrite"
      assert cmd_str =~ "chown -R"
    end

    test "passes builder args as env flags" do
      config = put_in(@config.builder, %Xamal.Configuration.Builder{
        docker: true,
        args: %{"HEX_KEY" => "secret123", "MIX_DEBUG" => "1"}
      })
      cmd = Builder.build_in_docker(config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "-e HEX_KEY=secret123"
      assert cmd_str =~ "-e MIX_DEBUG=1"
    end

    test "no env flags when args is nil" do
      config = put_in(@config.builder, %Xamal.Configuration.Builder{docker: true, args: nil})
      cmd = Builder.build_in_docker(config)
      cmd_str = Enum.join(cmd, " ")

      # Should not have any -e flags (except inside the sh -c script)
      [before_sh | _] = String.split(cmd_str, "sh -c")
      refute before_sh =~ "-e "
    end

    test "no env flags when args is empty" do
      config = put_in(@config.builder, %Xamal.Configuration.Builder{docker: true, args: %{}})
      cmd = Builder.build_in_docker(config)
      cmd_str = Enum.join(cmd, " ")

      [before_sh | _] = String.split(cmd_str, "sh -c")
      refute before_sh =~ "-e "
    end
  end

  describe "scp_tarball/3" do
    test "builds scp command" do
      ssh_config = %Xamal.Configuration.Ssh{user: "deploy", port: 22}
      result = Builder.scp_tarball(@config, "10.0.0.1", ssh_config)

      assert result =~ "scp"
      assert result =~ "deploy@10.0.0.1"
      assert result =~ "my_app-abc1234.tar.gz"
    end

    test "includes port when non-standard" do
      ssh_config = %Xamal.Configuration.Ssh{user: "deploy", port: 2222}
      result = Builder.scp_tarball(@config, "10.0.0.1", ssh_config)

      assert result =~ "-P 2222"
    end
  end

  describe "unpack_tarball/1" do
    test "unpacks and removes tarball" do
      cmd = Builder.unpack_tarball(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "tar -xzf"
      assert cmd_str =~ "/opt/xamal/my-app/releases/abc1234"
      assert cmd_str =~ "rm"
    end
  end
end
