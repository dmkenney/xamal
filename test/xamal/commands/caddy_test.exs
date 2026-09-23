defmodule Xamal.Commands.CaddyTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Caddy

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    roles: [%Xamal.Configuration.Role{name: "web", hosts: ["1.2.3.4"]}],
    boot: %Xamal.Configuration.Boot{},
    builder: %Xamal.Configuration.Builder{},
    caddy: %Xamal.Configuration.Caddy{host: "app.example.com", app_port: 4000, hosts: []},
    env: %Xamal.Configuration.Env{clear: %{}, secret_keys: [], secrets: nil},
    ssh: %Xamal.Configuration.Ssh{},
    release: %Xamal.Configuration.Release{name: "my_app", mix_env: "prod"},
    health_check: %Xamal.Configuration.HealthCheck{}
  }

  describe "install/0" do
    test "installs via apt" do
      cmd = Caddy.install()
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "apt-get"
      assert cmd_str =~ "caddy"
      assert cmd_str =~ "curl"
    end
  end

  describe "check_installed/0" do
    test "checks caddy version" do
      assert Caddy.check_installed() == ["caddy", "version"]
    end
  end

  describe "write_caddyfile/2" do
    test "writes caddyfile with upstream port" do
      cmd = Caddy.write_caddyfile(@config, 4000)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "echo"
      assert cmd_str =~ "app.example.com"
      assert cmd_str =~ "Caddyfile"
    end
  end

  describe "reload/0" do
    test "reloads from the system Caddyfile so every app on the host stays loaded" do
      assert Caddy.reload() == ["sudo", "caddy", "reload", "--config", "/etc/caddy/Caddyfile"]
    end
  end

  describe "start/0" do
    test "starts from the system Caddyfile" do
      assert Caddy.start() == ["caddy", "start", "--config", "/etc/caddy/Caddyfile"]
    end
  end

  describe "install/0 system Caddyfile" do
    test "replaces the package's default site with the import line" do
      cmd_str = Enum.join(Caddy.install(), " ")

      assert cmd_str =~ "echo 'import /opt/xamal/*/Caddyfile' | sudo tee /etc/caddy/Caddyfile"
    end
  end

  describe "import_ensure_script/1" do
    setup do
      path = Path.join(System.tmp_dir!(), "xamal_caddyfile_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    defp run_script(path) do
      {_, 0} = System.cmd("sh", ["-c", Caddy.import_ensure_script(path)])
      File.read!(path)
    end

    test "creates the file when it doesn't exist", %{path: path} do
      assert run_script(path) == "import /opt/xamal/*/Caddyfile\n"
    end

    test "appends the import after existing content, keeping it", %{path: path} do
      File.write!(path, "{\n  email ops@example.com\n}\n")

      assert run_script(path) ==
               "{\n  email ops@example.com\n}\nimport /opt/xamal/*/Caddyfile\n"
    end

    test "adds a newline first when the last line has none", %{path: path} do
      File.write!(path, "other.example.com {\n  respond ok\n}")

      assert run_script(path) ==
               "other.example.com {\n  respond ok\n}\nimport /opt/xamal/*/Caddyfile\n"
    end

    test "is idempotent", %{path: path} do
      run_script(path)
      assert run_script(path) == "import /opt/xamal/*/Caddyfile\n"
    end
  end

  describe "configure_system_caddyfile/0" do
    test "runs the import script with sudo against the system Caddyfile" do
      [sudo, "sh", "-c", script] = Caddy.configure_system_caddyfile()

      assert sudo == "sudo"
      assert script =~ "grep -qxF"
      assert script =~ "import /opt/xamal/*/Caddyfile"
      assert script =~ ">> /etc/caddy/Caddyfile"
    end
  end

  describe "enable/0" do
    test "enables and starts the caddy service" do
      assert Caddy.enable() == ["sudo", "systemctl", "enable", "--now", "caddy"]
    end
  end

  describe "catch_all_conflicts/1" do
    test "finds :80 catch-all sites in other services' Caddyfiles only" do
      cmd_str = Enum.join(Caddy.catch_all_conflicts(@config), " ")

      assert cmd_str =~ "grep -lx ':80 {' /opt/xamal/*/Caddyfile"
      assert cmd_str =~ "grep -vxF /opt/xamal/my-app/Caddyfile"
    end
  end

  describe "write_active_port/2" do
    test "writes port to file" do
      cmd = Caddy.write_active_port(@config, 4001)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "echo"
      assert cmd_str =~ "4001"
      assert cmd_str =~ "active_port"
    end
  end
end
