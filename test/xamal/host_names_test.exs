defmodule Xamal.HostNamesTest do
  use ExUnit.Case, async: true

  alias Xamal.{CommandOptions, Configuration, Context}
  alias Xamal.Commands.Hook

  @moduletag :tmp_dir

  defp write_config(dir, servers) do
    path = Path.join(dir, "xamal.exs")

    File.write!(path, """
    import Config

    config :xamal,
      service: "my-app",
      servers: #{servers}
    """)

    Configuration.create_from(config_file: path, version: "abc123")
  end

  defp new_config(servers) do
    Configuration.new(%{"service" => "my-app", "servers" => servers}, version: "abc123")
  end

  describe "config file" do
    test "named hosts keep their order and connect by address", %{tmp_dir: dir} do
      config =
        write_config(dir, ~s([web: [west: "10.0.0.2", east: "10.0.0.1"]]))

      assert Configuration.all_hosts(config) == ["10.0.0.2", "10.0.0.1"]
      assert Configuration.primary_host(config) == "10.0.0.2"
      assert Configuration.host_names(config) == %{"10.0.0.1" => "east", "10.0.0.2" => "west"}
    end

    test "bare strings still work", %{tmp_dir: dir} do
      config = write_config(dir, ~s([web: ["10.0.0.1", "10.0.0.2"]]))

      assert Configuration.all_hosts(config) == ["10.0.0.1", "10.0.0.2"]
      assert Configuration.host_names(config) == %{}
    end

    test "mixes bare and named hosts", %{tmp_dir: dir} do
      config = write_config(dir, ~s([web: ["10.0.0.3", east: "10.0.0.1"]]))

      assert Configuration.all_hosts(config) == ["10.0.0.3", "10.0.0.1"]
      assert Configuration.host_name(config, "10.0.0.1") == "east"
      assert Configuration.host_name(config, "10.0.0.3") == nil
    end

    test "named hosts under a role's hosts key", %{tmp_dir: dir} do
      config =
        write_config(
          dir,
          ~s([web: [east: "10.0.0.1"], worker: [hosts: [jobs: "10.0.0.5"], cmd: "bin/worker"]])
        )

      worker = Configuration.role(config, "worker")
      assert worker.hosts == ["10.0.0.5"]
      assert worker.cmd == "bin/worker"
      assert Configuration.host_name(config, "10.0.0.5") == "jobs"
    end

    test "named hosts in a map-based role", %{tmp_dir: dir} do
      config =
        write_config(
          dir,
          ~s([web: %{hosts: [west: "10.0.0.2", east: "10.0.0.1"], cmd: "bin/web"}])
        )

      web = Configuration.role(config, "web")
      assert web.hosts == ["10.0.0.2", "10.0.0.1"]
      assert web.cmd == "bin/web"
      assert Configuration.host_name(config, "10.0.0.1") == "east"
    end

    test "implicit web role from a plain list", %{tmp_dir: dir} do
      config = write_config(dir, ~s(["10.0.0.1", east: "10.0.0.2"]))

      assert Configuration.role(config, "web").hosts == ["10.0.0.1", "10.0.0.2"]
      assert Configuration.host_name(config, "10.0.0.2") == "east"
    end
  end

  describe "validation" do
    test "rejects a name used for two addresses" do
      assert_raise ArgumentError, ~r/Host name 'east' is used for more than one address/, fn ->
        new_config(%{"web" => [%{"east" => "10.0.0.1"}, %{"east" => "10.0.0.2"}]})
      end
    end

    test "rejects an address with two names" do
      assert_raise ArgumentError, ~r/Host 10.0.0.1 has more than one name/, fn ->
        new_config(%{"web" => [%{"east" => "10.0.0.1"}], "job" => [%{"west" => "10.0.0.1"}]})
      end
    end

    test "rejects an address with two names in one role", %{tmp_dir: dir} do
      assert_raise ArgumentError, ~r/Host 10.0.0.1 has more than one name: east, west/, fn ->
        write_config(dir, ~s([web: [east: "10.0.0.1", west: "10.0.0.1"]]))
      end
    end

    test "allows the same named host in several roles" do
      config =
        new_config(%{"web" => [%{"east" => "10.0.0.1"}], "job" => [%{"east" => "10.0.0.1"}]})

      assert Configuration.all_hosts(config) == ["10.0.0.1"]
    end

    test "rejects a name that is another host's address" do
      assert_raise ArgumentError, ~r/also the address of another host/, fn ->
        new_config(%{"web" => ["10.0.0.2", %{"10.0.0.2" => "10.0.0.1"}]})
      end
    end

    test "rejects a non-string address" do
      assert_raise ArgumentError, ~r/must map to an address string/, fn ->
        new_config(%{"web" => [%{"east" => 42}]})
      end
    end
  end

  describe "host targeting" do
    setup do
      config =
        new_config(%{
          "web" => [%{"east" => "10.116.103.172"}, %{"west" => "10.116.236.144"}],
          "job" => ["10.200.0.1"]
        })

      %{config: config}
    end

    defp hosts_for(config, filter) do
      config |> CommandOptions.build_context(hosts: filter) |> Context.hosts()
    end

    test "matches by name", %{config: config} do
      assert hosts_for(config, "east") == ["10.116.103.172"]
      assert hosts_for(config, "east,west") == ["10.116.103.172", "10.116.236.144"]
    end

    test "matches by address and wildcard", %{config: config} do
      assert hosts_for(config, "10.116.236.144") == ["10.116.236.144"]
      assert hosts_for(config, "10.116.*") == ["10.116.103.172", "10.116.236.144"]
      assert hosts_for(config, "w*") == ["10.116.236.144"]
    end

    test "fails when a pattern matches no host", %{config: config} do
      assert_raise Mix.Error, ~r/No configured host matches "nowhere"/, fn ->
        hosts_for(config, "east,nowhere")
      end
    end

    test "fails on an empty filter", %{config: config} do
      assert_raise Mix.Error, ~r/at least one host/, fn -> hosts_for(config, ",") end
    end

    test "primary filter still uses the address", %{config: config} do
      context = CommandOptions.build_context(config, primary: true)
      assert Context.hosts(context) == ["10.116.103.172"]
    end
  end

  test "host_label shows name and address" do
    config = new_config(%{"web" => [%{"east" => "10.0.0.1"}, "10.0.0.2"]})

    assert Configuration.host_label(config, "10.0.0.1") == "east (10.0.0.1)"
    assert Configuration.host_label(config, "10.0.0.2") == "10.0.0.2"
  end

  test "hook env keeps addresses in XAMAL_HOSTS and adds XAMAL_HOST_NAMES" do
    config = new_config(%{"web" => [%{"east" => "10.0.0.1"}, "10.0.0.2"]})
    env = Hook.env(config)

    assert env["XAMAL_HOSTS"] == "10.0.0.1,10.0.0.2"
    assert env["XAMAL_HOST_NAMES"] == "east,10.0.0.2"
  end
end
