defmodule Xamal.Commands.LockTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Lock

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

  describe "acquire/3" do
    test "creates lock directory and writes details" do
      cmd = Lock.acquire(@config, "deploying", "abc123")
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "mkdir"
      assert cmd_str =~ "lock-my-app"
      assert cmd_str =~ "echo"
      assert cmd_str =~ "details"
    end
  end

  describe "release/1" do
    test "removes lock directory" do
      cmd = Lock.release(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "rm"
      assert cmd_str =~ "lock-my-app"
    end

    test "does not use && so release succeeds even if details file is missing" do
      cmd = Lock.release(@config)
      cmd_str = Enum.join(cmd, " ")

      refute cmd_str =~ "&&"
    end
  end

  describe "ensure_locks_directory/1" do
    test "creates parent run directory with mkdir -p" do
      cmd = Lock.ensure_locks_directory(@config)
      assert cmd == ["mkdir", "-p", "~/.xamal"]
    end
  end

  describe "status/1" do
    test "stats lock dir and reads details" do
      cmd = Lock.status(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "stat"
      assert cmd_str =~ "cat"
      assert cmd_str =~ "base64"
    end
  end
end
