defmodule Xamal.Commands.AppTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.App

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    version: "abc1234",
    roles: [%Xamal.Configuration.Role{name: "web", hosts: ["1.2.3.4"]}],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{app_port: 4000},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{}
  }

  describe "stop/1" do
    test "builds stop command" do
      cmd = App.stop(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "bin/my_app"
      assert cmd_str =~ "stop"
      assert cmd_str =~ "current"
    end
  end

  describe "current_version/1" do
    test "reads current symlink" do
      cmd = App.current_version(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "readlink"
      assert cmd_str =~ "current"
      assert cmd_str =~ "basename"
    end
  end

  describe "exec/3" do
    test "non-interactive uses rpc" do
      cmd = App.exec(@config, "MyApp.hello()")
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "rpc"
    end

    test "sources app.sh, falling back to app.env on hosts without it" do
      cmd_str = @config |> App.exec("MyApp.hello()") |> Enum.join(" ")

      assert cmd_str =~
               "if [ -f /opt/xamal/my-app/env/app.sh ]; then . /opt/xamal/my-app/env/app.sh; " <>
                 "else set -a; . /opt/xamal/my-app/env/app.env; set +a; fi"
    end

    test "interactive uses remote" do
      cmd = App.exec(@config, "", interactive: true)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "remote"
    end
  end

  describe "logs/2" do
    test "builds journalctl command with wildcard unit" do
      cmd = App.logs(@config, lines: 50)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "journalctl"
      assert cmd_str =~ "-n 50"
      assert cmd_str =~ "my_app@*"
    end

    test "with specific port" do
      cmd = App.logs(@config, lines: 50, port: 4000)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "journalctl"
      assert cmd_str =~ "-u my_app@4000"
      refute cmd_str =~ "@*"
    end

    test "with grep" do
      cmd = App.logs(@config, grep: "error")
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "journalctl"
      assert cmd_str =~ "grep"
    end

    test "with follow" do
      cmd = App.logs(@config, follow: true)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "-f"
    end
  end

  describe "list_releases/1" do
    test "lists release directory" do
      cmd = App.list_releases(@config)
      assert cmd == ["ls", "-1t", "/opt/xamal/my-app/releases"]
    end
  end

  describe "stale_releases/2" do
    test "skips N most recent" do
      cmd = App.stale_releases(@config, 3)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "ls -1t"
      assert cmd_str =~ "tail -n +4"
    end
  end

  describe "details/1" do
    test "shows release info" do
      cmd = App.details(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "readlink"
      assert cmd_str =~ "version"
      assert cmd_str =~ "pid"
    end
  end
end
