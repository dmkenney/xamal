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
    health_check: %Xamal.Configuration.HealthCheck{},
    aliases: %{}
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
