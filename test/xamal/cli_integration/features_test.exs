defmodule Xamal.CLIIntegration.FeaturesTest do
  use ExUnit.Case, async: true
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # -- Git dirty check --

  test "deploy aborts when git tree is dirty", %{dir: dir} do
    setup_config(dir)
    setup_git_repo(dir)
    File.write!(Path.join(dir, "dirty.txt"), "uncommitted")

    {output, code} = xamal(["deploy"], dir)
    assert code != 0
    assert output =~ "uncommitted changes detected"
  end

  test "deploy proceeds with --skip-dirty-check when dirty", %{dir: dir} do
    setup_config(dir)
    setup_git_repo(dir)
    File.write!(Path.join(dir, "dirty.txt"), "uncommitted")

    # Will fail later (no SSH), but should get past the dirty check
    {output, _code} = xamal(["deploy", "--skip-dirty-check"], dir)
    refute output =~ "uncommitted changes detected"
  end

  test "deploy proceeds when git tree is clean", %{dir: dir} do
    setup_config(dir)
    setup_git_repo(dir)

    # Will fail later (no SSH), but should get past the dirty check
    {output, _code} = xamal(["deploy"], dir)
    refute output =~ "uncommitted changes detected"
  end

  # -- Aliases --

  test "alias dispatches to target command", %{dir: dir} do
    setup_config(dir)
    # "info" is aliased to "config" in our test deploy.yml
    {output, 0} = xamal(["info"], dir)
    assert output =~ "Service: test-app"
    assert output =~ "Caddy: test.example.com"
  end

  # -- Global options --

  test "custom config file path", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["config", "-c", "config/deploy.yml"], dir)
    assert output =~ "Service: test-app"
  end

  # -- Destinations --

  test "destination file overrides base config", %{dir: dir} do
    setup_config(dir)

    staging_yml = """
    servers:
      web:
        - 10.0.1.1
    caddy:
      host: staging.example.com
      app_port: 4000
    """

    File.write!(Path.join(dir, "config/deploy.staging.yml"), staging_yml)

    {output, 0} = xamal(["config", "-d", "staging"], dir)
    assert output =~ "Destination: staging"
    assert output =~ "web: 10.0.1.1"
    assert output =~ "Caddy: staging.example.com"
    # Service name from base is preserved
    assert output =~ "Service: test-app"
  end

  test "destination without file uses base config", %{dir: dir} do
    setup_config(dir)

    {output, 0} = xamal(["config", "-d", "production"], dir)
    assert output =~ "Destination: production"
    # Falls back to base config values
    assert output =~ "web: 10.0.0.1, 10.0.0.2"
    assert output =~ "Caddy: test.example.com"
  end

  # -- EEx interpolation --

  test "config supports env[] binding", %{dir: dir} do
    eex_yml = """
    service: <%= env["XAMAL_TEST_SERVICE"] || "fallback-app" %>
    servers:
      web:
        - 10.0.0.1
    caddy:
      host: app.example.com
    """

    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/deploy.yml"), eex_yml)
    File.mkdir_p!(Path.join(dir, ".xamal"))
    File.write!(Path.join(dir, ".xamal/secrets"), "")

    {output, 0} = xamal(["config"], dir)
    assert output =~ "Service: fallback-app"
  end

  test "config supports System.get_env", %{dir: dir} do
    eex_yml = """
    service: <%= System.get_env("XAMAL_TEST_SVC") || "sys-app" %>
    servers:
      web:
        - 10.0.0.1
    caddy:
      host: app.example.com
    """

    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/deploy.yml"), eex_yml)
    File.mkdir_p!(Path.join(dir, ".xamal"))
    File.write!(Path.join(dir, ".xamal/secrets"), "")

    {output, 0} = xamal(["config"], dir)
    assert output =~ "Service: sys-app"
  end

  # -- Docs --

  test "docs without topic shows topic list", %{dir: dir} do
    {output, 0} = xamal(["docs"], dir)
    assert output =~ "Xamal Configuration Reference"
    assert output =~ "config"
    assert output =~ "servers"
    assert output =~ "caddy"
    assert output =~ "secrets"
    assert output =~ "destinations"
  end

  test "docs with topic shows documentation", %{dir: dir} do
    {output, 0} = xamal(["docs", "caddy"], dir)
    assert output =~ "Caddy Configuration"
    assert output =~ "app_port"
    assert output =~ "Let's Encrypt"
  end

  test "docs with unknown topic shows topic list", %{dir: dir} do
    {output, 0} = xamal(["docs", "nonexistent"], dir)
    assert output =~ "Unknown topic: nonexistent"
    assert output =~ "Xamal Configuration Reference"
  end
end
