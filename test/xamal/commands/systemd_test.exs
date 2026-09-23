defmodule Xamal.Commands.SystemdTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Systemd

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    roles: [%Xamal.Configuration.Role{name: "web", hosts: ["1.2.3.4"]}],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{host: "app.example.com", app_port: 4000, hosts: []},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{user: "deploy"},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{}
  }

  @role %Xamal.Configuration.Role{name: "web", hosts: ["1.2.3.4"]}

  describe "generate_unit_content/1" do
    test "generates valid systemd unit with placeholders" do
      content = Systemd.generate_unit_content(@config)

      assert content =~ "Description=my_app (%i)"
      assert content =~ "User=deploy"
      assert content =~ "WorkingDirectory=/opt/xamal/my-app/current"
      assert content =~ "EnvironmentFile=-/opt/xamal/my-app/env/app.env"
      assert content =~ "Environment=PORT=%i"
      assert content =~ "Environment=RELEASE_NODE=my_app_%i"
      assert content =~ "ExecStart=/opt/xamal/my-app/current/bin/my_app start"
      assert content =~ "Restart=on-failure"
      assert content =~ "RestartSec=5"
      assert content =~ "TimeoutStopSec=30"
      assert content =~ "WantedBy=multi-user.target"
    end

    test "uses drain_timeout from config for TimeoutStopSec" do
      config = %{@config | raw_config: Map.put(@config.raw_config, "drain_timeout", 10)}
      content = Systemd.generate_unit_content(config)

      assert content =~ "TimeoutStopSec=10"
      refute content =~ "TimeoutStopSec=30"
    end

    test "uses Type=exec" do
      content = Systemd.generate_unit_content(@config)
      assert content =~ "Type=exec"
    end
  end

  describe "install_unit/1" do
    test "writes unit file and reloads daemon" do
      cmd = Systemd.install_unit(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "echo"
      assert cmd_str =~ "sudo tee /etc/systemd/system/my_app@.service"
      assert cmd_str =~ "sudo systemctl daemon-reload"
    end
  end

  describe "sync_unit/1" do
    test "stages the unit, replaces it only when it differs, and reports the update" do
      [sh, "-c", script] = Systemd.sync_unit(@config)

      assert sh == "sh"
      assert script =~ "sudo tee /etc/systemd/system/my_app@.service.xamal-new"

      assert script =~
               "cmp -s /etc/systemd/system/my_app@.service.xamal-new " <>
                 "/etc/systemd/system/my_app@.service"

      assert script =~ "sudo systemctl daemon-reload && echo unit-updated"
      assert script =~ "TimeoutStopSec=30"
    end

    test "writes the same content bootstrap installs" do
      [_, _, script] = Systemd.sync_unit(@config)

      # Bootstrap's install_unit and sync_unit must render identical files, or
      # every deploy after a bootstrap would report a spurious update.
      content = Systemd.generate_unit_content(@config)
      first_line = content |> String.split("\n") |> hd()
      assert script =~ first_line
      assert Enum.join(Systemd.install_unit(@config), " ") =~ first_line
    end
  end

  describe "units_under_other_names/1" do
    test "finds unit files for this service directory, minus this release's own" do
      cmd_str = Enum.join(Systemd.units_under_other_names(@config), " ")

      assert cmd_str =~
               "grep -lxF 'WorkingDirectory=/opt/xamal/my-app/current' " <>
                 "/etc/systemd/system/*@.service"

      assert cmd_str =~ "grep -vxF /etc/systemd/system/my_app@.service"
    end
  end

  describe "start/2" do
    test "starts service instance on given port" do
      assert Systemd.start(@config, 4000) == ["sudo", "systemctl", "start", "my_app@4000"]
    end
  end

  describe "stop/2" do
    test "stops service instance on given port" do
      assert Systemd.stop(@config, 4001) == ["sudo", "systemctl", "stop", "my_app@4001"]
    end
  end

  describe "enable/2" do
    test "enables service instance for boot" do
      assert Systemd.enable(@config, 4000) == ["sudo", "systemctl", "enable", "my_app@4000"]
    end
  end

  describe "disable/2" do
    test "disables service instance from boot" do
      assert Systemd.disable(@config, 4001) == ["sudo", "systemctl", "disable", "my_app@4001"]
    end
  end

  describe "stop_all/1" do
    test "stops both port instances with chain" do
      cmd = Systemd.stop_all(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "sudo systemctl stop my_app@4000"
      assert cmd_str =~ ";"
      assert cmd_str =~ "sudo systemctl stop my_app@4001"
    end
  end

  describe "disable_all/1" do
    test "disables both port instances with chain" do
      cmd = Systemd.disable_all(@config)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "sudo systemctl disable my_app@4000"
      assert cmd_str =~ ";"
      assert cmd_str =~ "sudo systemctl disable my_app@4001"
    end
  end

  describe "remove_unit/1" do
    test "removes unit file and reloads daemon" do
      cmd = Systemd.remove_unit(@config)

      assert cmd == [
               "sudo",
               "rm",
               "-f",
               "/etc/systemd/system/my_app@.service",
               "&&",
               "sudo",
               "systemctl",
               "daemon-reload"
             ]
    end
  end

  describe "unit_owned_by_other_service/1" do
    test "checks the unit exists and points at a different service directory" do
      cmd_str = Enum.join(Systemd.unit_owned_by_other_service(@config), " ")

      assert cmd_str ==
               "test -f /etc/systemd/system/my_app@.service && " <>
                 "! grep -qxF 'WorkingDirectory=/opt/xamal/my-app/current' " <>
                 "/etc/systemd/system/my_app@.service"
    end
  end

  describe "port_conflicts/1" do
    test "lists units on both ports, minus this release's own instances" do
      cmd_str = Enum.join(Systemd.port_conflicts(@config), " ")

      assert cmd_str =~
               "systemctl list-units --all --plain --no-legend '*@4000.service' '*@4001.service'"

      assert cmd_str =~ "grep -vxF -e my_app@4000.service -e my_app@4001.service"
    end

    test "the filter keeps only other releases' units" do
      # Everything after the systemctl stage, fed canned list-units output.
      filter =
        @config
        |> Systemd.port_conflicts()
        |> Enum.drop_while(&(&1 != "|"))
        |> tl()
        |> Enum.join(" ")

      input =
        "my_app@4000.service loaded active running my_app (4000)\n" <>
          "other@4001.service loaded active running other (4001)\n"

      {out, 0} = System.cmd("sh", ["-c", "printf '#{input}' | #{filter}"])
      assert out == "other@4001.service\n"

      {_, status} =
        System.cmd("sh", ["-c", "printf 'my_app@4000.service loaded\\n' | #{filter}"])

      assert status != 0
    end
  end

  describe "write_env_symlink/2" do
    test "symlinks role env to app.env" do
      cmd = Systemd.write_env_symlink(@config, @role)

      assert cmd == [
               "ln",
               "-sfn",
               "/opt/xamal/my-app/env/roles/web.env",
               "/opt/xamal/my-app/env/app.env"
             ]
    end
  end
end
