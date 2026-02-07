defmodule Xamal.CLIIntegration.ConfigTest do
  use ExUnit.Case, async: true
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    setup_config(dir)
    %{dir: dir}
  end

  test "shows full configuration", %{dir: dir} do
    {output, 0} = xamal(["config"], dir)
    assert output =~ "Service: test-app"
    assert output =~ "web: 10.0.0.1, 10.0.0.2"
    assert output =~ "worker: 10.0.0.3"
    assert output =~ "SSH: deploy@*:22"
    assert output =~ "Release: test_app (prod)"
    assert output =~ "Caddy: test.example.com -> port 4000"
    assert output =~ "Destination: (none)"
  end

  test "shows destination when specified", %{dir: dir} do
    {output, 0} = xamal(["config", "-d", "staging"], dir)
    assert output =~ "Destination: staging"
  end

  test "build details shows build configuration", %{dir: dir} do
    {output, 0} = xamal(["build", "details"], dir)
    assert output =~ "Build configuration:"
    assert output =~ "Release name: test_app"
    assert output =~ "Mix env: prod"
    assert output =~ "Builder: local"
    assert output =~ "Tarball:"
  end

  test "secrets print prints secrets with redaction", %{dir: dir} do
    {output, 0} = xamal(["secrets", "print"], dir)
    assert output =~ "SECRET_KEY_BASE"
    assert output =~ "[REDACTED]"
    refute output =~ "super_secret_value_123"
  end
end
