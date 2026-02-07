defmodule Xamal.Commands.HookTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Hook

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app", "hooks_path" => ".xamal/hooks"},
    version: "abc1234",
    roles: [
      %Xamal.Configuration.Role{name: "web", hosts: ["10.0.0.1", "10.0.0.2"]}
    ],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{},
    aliases: %{}
  }

  describe "run/2" do
    test "returns hook script path" do
      cmd = Hook.run(@config, "pre-deploy")
      assert cmd == [".xamal/hooks/pre-deploy"]
    end
  end

  describe "env/2" do
    test "builds environment variables map" do
      env = Hook.env(@config)

      assert env["XAMAL_SERVICE"] == "my-app"
      assert env["XAMAL_VERSION"] == "abc1234"
      assert env["XAMAL_HOSTS"] == "10.0.0.1,10.0.0.2"
    end

    test "includes command details" do
      env = Hook.env(@config, %{command: "deploy", subcommand: "app"})

      assert env["XAMAL_COMMAND"] == "deploy"
      assert env["XAMAL_SUBCOMMAND"] == "app"
    end

    test "defaults to empty strings for missing details" do
      env = Hook.env(@config)

      assert env["XAMAL_COMMAND"] == ""
      assert env["XAMAL_DESTINATION"] == ""
      assert env["XAMAL_ROLE"] == ""
    end

    test "includes XAMAL_RECORDED_AT as ISO 8601 timestamp" do
      env = Hook.env(@config)

      assert env["XAMAL_RECORDED_AT"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end

    test "includes XAMAL_PERFORMER" do
      env = Hook.env(@config)

      # Should be non-empty (git user or whoami fallback)
      assert is_binary(env["XAMAL_PERFORMER"])
      assert env["XAMAL_PERFORMER"] != ""
    end

    test "includes XAMAL_SERVICE_VERSION in service@version format" do
      env = Hook.env(@config)

      assert env["XAMAL_SERVICE_VERSION"] == "my-app@abc1234"
    end

    test "includes XAMAL_LOCK status" do
      env = Hook.env(@config)

      assert env["XAMAL_LOCK"] in ["true", "false"]
    end
  end

  describe "hook_exists?/2" do
    test "returns false for non-existent hook" do
      refute Hook.hook_exists?(@config, "non-existent")
    end
  end
end
