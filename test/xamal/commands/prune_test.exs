defmodule Xamal.Commands.PruneTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Prune

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app", "retain_releases" => 5},
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

  describe "releases/1" do
    test "excludes current version and removes old releases" do
      cmd = Prune.releases(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "ls -1t"
      assert cmd_str =~ "/opt/xamal/my-app/releases"
      assert cmd_str =~ "grep -v"
      assert cmd_str =~ "readlink -f"
      assert cmd_str =~ "tail -n +6"
      assert cmd_str =~ "xargs"
      assert cmd_str =~ "rm -rf"
    end

    test "respects retain_releases setting" do
      config = %{@config | raw_config: Map.put(@config.raw_config, "retain_releases", 3)}
      cmd = Prune.releases(config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "tail -n +4"
    end
  end
end
