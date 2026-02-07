defmodule Xamal.Commands.AuditorTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Auditor

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

  describe "record/3" do
    test "builds audit log append command" do
      cmd = Auditor.record(@config, "Deployed version abc1234")
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "mkdir -p"
      assert cmd_str =~ "~/.xamal"
      assert cmd_str =~ "echo"
      assert cmd_str =~ "Deployed version abc1234"
      assert cmd_str =~ ">>"
      assert cmd_str =~ "my-app-audit.log"
    end

    test "includes details tags" do
      cmd = Auditor.record(@config, "Deployed", %{version: "abc1234", role: "web"})
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "my-app"
      assert cmd_str =~ "Deployed"
    end
  end

  describe "reveal/1" do
    test "tails audit log" do
      cmd = Auditor.reveal(@config)
      assert cmd == ["tail", "-n", "50", "~/.xamal/my-app-audit.log"]
    end
  end
end
