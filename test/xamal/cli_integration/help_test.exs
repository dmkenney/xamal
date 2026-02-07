defmodule Xamal.CLIIntegration.HelpTest do
  use ExUnit.Case, async: true
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "version outputs version string", %{dir: dir} do
    {output, 0} = xamal(["version"], dir)
    assert output =~ "Xamal #{Xamal.version()}"
  end

  test "no args shows usage", %{dir: dir} do
    {output, 0} = xamal([], dir)
    assert output =~ "Usage: xamal <command>"
    assert output =~ "setup"
    assert output =~ "deploy"
    assert output =~ "rollback"
  end

  test "--help flag shows usage", %{dir: dir} do
    {output, 0} = xamal(["--help"], dir)
    assert output =~ "Usage: xamal"
  end

  test "app help", %{dir: dir} do
    {output, 0} = xamal(["app"], dir)
    assert output =~ "Usage: xamal app"
    assert output =~ "boot"
    assert output =~ "stop"
    assert output =~ "exec"
    assert output =~ "logs"
    assert output =~ "maintenance"
    assert output =~ "live"
  end

  test "app --help flag", %{dir: dir} do
    {output, 0} = xamal(["app", "--help"], dir)
    assert output =~ "Usage: xamal app"
  end

  test "build help", %{dir: dir} do
    {output, 0} = xamal(["build"], dir)
    assert output =~ "Usage: xamal build"
    assert output =~ "deliver"
    assert output =~ "push"
    assert output =~ "pull"
  end

  test "lock help", %{dir: dir} do
    {output, 0} = xamal(["lock"], dir)
    assert output =~ "Usage: xamal lock"
    assert output =~ "status"
    assert output =~ "acquire"
    assert output =~ "release"
    assert output =~ "-m"
  end

  test "secrets help", %{dir: dir} do
    {output, 0} = xamal(["secrets"], dir)
    assert output =~ "Usage: xamal secrets"
    assert output =~ "fetch"
    assert output =~ "extract"
    assert output =~ "print"
    assert output =~ "1password"
    assert output =~ "aws_secrets_manager"
    assert output =~ "bitwarden"
    assert output =~ "doppler"
    assert output =~ "gcp_secret_manager"
    assert output =~ "last_pass"
    assert output =~ "passbolt"
  end

  test "server help", %{dir: dir} do
    {output, 0} = xamal(["server"], dir)
    assert output =~ "Usage: xamal server"
    assert output =~ "exec"
    assert output =~ "bootstrap"
  end
end
