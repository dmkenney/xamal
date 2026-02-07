defmodule Xamal.Commands.ServerTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Server

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    roles: [%Xamal.Configuration.Role{name: "web", hosts: ["1.2.3.4"]}],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{},
    aliases: %{}
  }

  describe "bootstrap/1" do
    test "creates all directories" do
      cmd = Server.bootstrap(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "mkdir -p /opt/xamal/my-app/releases"
      assert cmd_str =~ "mkdir -p /opt/xamal/my-app/env/roles"
      assert cmd_str =~ "mkdir -p /opt/xamal/my-app/shared"
      assert cmd_str =~ "mkdir -p ~/.xamal"
    end
  end

  describe "link_current/2" do
    test "symlinks to release version" do
      cmd = Server.link_current(@config, "abc1234")

      assert cmd == [
               "ln",
               "-sfn",
               "/opt/xamal/my-app/releases/abc1234",
               "/opt/xamal/my-app/current"
             ]
    end
  end

  describe "list_releases/1" do
    test "lists releases directory" do
      cmd = Server.list_releases(@config)
      assert cmd == ["ls", "-1", "/opt/xamal/my-app/releases"]
    end
  end
end
