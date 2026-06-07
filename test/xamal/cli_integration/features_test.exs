defmodule Xamal.MixTaskIntegration.FeaturesTest do
  use ExUnit.Case, async: false
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # -- Global options --

  test "custom config file path", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["config", "-c", "config/xamal.exs"], dir)
    assert output =~ "Service: test-app"
  end

  test "a leading boolean global flag is accepted, not rejected", %{dir: dir} do
    setup_config(dir)
    # Regression guard: the global parser used to raise "Unknown option" on any
    # leading flag, breaking commands like `mix xamal.app.logs -f`.
    {output, 0} = xamal(["config", "-v"], dir)
    assert output =~ "Service: test-app"
    refute output =~ "Unknown option"
  end

  test "globals are parsed when mixed with other leading flags", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["config", "-v", "-c", "config/xamal.exs"], dir)
    assert output =~ "Service: test-app"
    refute output =~ "Unknown option"
  end

  # -- Destinations --

  test "destination file overrides base config", %{dir: dir} do
    setup_config(dir)

    staging_config = """
    import Config

    config :xamal,
      servers: [
        web: ["10.0.1.1"]
      ],
      caddy: [
        host: "staging.example.com",
        app_port: 4000
      ]
    """

    File.mkdir_p!(Path.join(dir, "config/xamal"))
    File.write!(Path.join(dir, "config/xamal/staging.exs"), staging_config)

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

  # -- Elixir config --

  test "config supports Elixir expressions", %{dir: dir} do
    config = """
    import Config

    config :xamal,
      service: System.get_env("XAMAL_TEST_SVC") || "sys-app",
      servers: [web: ["10.0.0.1"]],
      caddy: [host: "app.example.com"]
    """

    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/xamal.exs"), config)
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
