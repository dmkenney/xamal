defmodule Xamal.Configuration.RoleTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.{Role, Env}

  @raw_config %{"service" => "my-app"}

  describe "new/4" do
    test "creates role from host list" do
      role = Role.new("web", ["10.0.0.1", "10.0.0.2"], @raw_config, nil)

      assert role.name == "web"
      assert role.hosts == ["10.0.0.1", "10.0.0.2"]
      assert role.cmd == nil
      assert role.env == nil
    end

    test "creates role from map config with hosts" do
      config = %{"hosts" => ["10.0.0.1"], "cmd" => "bin/worker start"}
      role = Role.new("worker", config, @raw_config, nil)

      assert role.name == "worker"
      assert role.hosts == ["10.0.0.1"]
      assert role.cmd == "bin/worker start"
    end

    test "parses tags" do
      config = %{"hosts" => ["10.0.0.1"], "tags" => ["db", "cache"]}
      role = Role.new("web", config, @raw_config, nil)

      assert role.tags == ["db", "cache"]
    end

    test "creates role-specific env" do
      config = %{
        "hosts" => ["10.0.0.1"],
        "env" => %{"clear" => %{"ROLE" => "worker"}}
      }

      role = Role.new("worker", config, @raw_config, nil)
      assert role.env != nil
      assert role.env.clear == %{"ROLE" => "worker"}
    end
  end

  describe "primary_host/1" do
    test "returns first host" do
      role = %Role{name: "web", hosts: ["10.0.0.1", "10.0.0.2"]}
      assert Role.primary_host(role) == "10.0.0.1"
    end

    test "returns nil for empty hosts" do
      role = %Role{name: "web", hosts: []}
      assert Role.primary_host(role) == nil
    end
  end

  describe "resolved_env/2" do
    test "returns global env when role has no env" do
      global = %Env{clear: %{"A" => "1"}, secret_keys: [], secrets: nil}
      role = %Role{name: "web", hosts: [], env: nil}

      assert Role.resolved_env(role, global) == global
    end

    test "merges global and role env" do
      global = %Env{clear: %{"A" => "1"}, secret_keys: ["SECRET_A"], secrets: nil}
      role_env = %Env{clear: %{"B" => "2"}, secret_keys: ["SECRET_B"], secrets: nil}
      role = %Role{name: "web", hosts: [], env: role_env}

      merged = Role.resolved_env(role, global)
      assert merged.clear == %{"A" => "1", "B" => "2"}
      assert merged.secret_keys == ["SECRET_A", "SECRET_B"]
    end
  end

  describe "secrets_path/2" do
    test "returns remote env file path" do
      config = %Xamal.Configuration{
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

      role = %Role{name: "web", hosts: []}
      assert Role.secrets_path(role, config) == "/opt/xamal/my-app/env/roles/web.env"
    end
  end
end
