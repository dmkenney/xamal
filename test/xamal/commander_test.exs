defmodule Xamal.CommanderTest do
  use ExUnit.Case, async: true

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    version: "abc1234",
    roles: [
      %Xamal.Configuration.Role{name: "web", hosts: ["10.0.0.1", "10.0.0.2"]},
      %Xamal.Configuration.Role{name: "worker", hosts: ["10.0.0.3"]}
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

  setup do
    name = :"commander_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Xamal.Commander.start_link(name: name)
    {:ok, name: name}
  end

  test "starts unconfigured", %{name: name} do
    refute Xamal.Commander.configured?(name)
  end

  test "configure sets config", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    assert Xamal.Commander.configured?(name)
    assert Xamal.Commander.config(name) == @config
  end

  test "hosts returns all hosts when no filters", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    hosts = Xamal.Commander.hosts(name)
    assert Enum.sort(hosts) == ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
  end

  test "specific_hosts filters", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    Xamal.Commander.set_specific_hosts(["10.0.0.1"], name)
    assert Xamal.Commander.hosts(name) == ["10.0.0.1"]
  end

  test "specific_roles filters", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    Xamal.Commander.set_specific_roles(["worker"], name)
    assert Xamal.Commander.hosts(name) == ["10.0.0.3"]
  end

  test "wildcard role matching", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    Xamal.Commander.set_specific_roles(["w*"], name)
    hosts = Xamal.Commander.hosts(name) |> Enum.sort()
    assert hosts == ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
  end

  test "roles returns filtered roles", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    Xamal.Commander.set_specific_roles(["web"], name)
    roles = Xamal.Commander.roles(name)
    assert length(roles) == 1
    assert hd(roles).name == "web"
  end

  test "primary_host", %{name: name} do
    Xamal.Commander.configure(@config, name: name)
    assert Xamal.Commander.primary_host(name) == "10.0.0.1"
  end

  test "lock state", %{name: name} do
    refute Xamal.Commander.holding_lock?(name)
    Xamal.Commander.set_holding_lock(true, name)
    assert Xamal.Commander.holding_lock?(name)
    Xamal.Commander.set_holding_lock(false, name)
    refute Xamal.Commander.holding_lock?(name)
  end
end
