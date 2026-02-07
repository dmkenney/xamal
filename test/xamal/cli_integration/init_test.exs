defmodule Xamal.CLIIntegration.InitTest do
  use ExUnit.Case, async: true
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "creates config files with expected content and executable hooks", %{dir: dir} do
    {output, 0} = xamal(["init"], dir)

    assert output =~ "Created configuration file"
    assert output =~ "Created .xamal/secrets"
    assert output =~ "Created sample hooks"

    assert File.exists?(Path.join(dir, "config/deploy.yml"))
    assert File.exists?(Path.join(dir, ".xamal/secrets"))

    # All 7 hooks should be created and executable
    for hook <-
          ~w(pre-build pre-deploy post-deploy pre-app-boot post-app-boot pre-caddy-reload post-caddy-reload) do
      path = Path.join(dir, ".xamal/hooks/#{hook}")
      assert File.exists?(path), "Expected hook #{hook} to exist"
      %{mode: mode} = File.stat!(path)
      assert Bitwise.band(mode, 0o111) != 0, "Expected hook #{hook} to be executable"
    end

    # Verify deploy.yml content
    content = File.read!(Path.join(dir, "config/deploy.yml"))
    assert content =~ "service: my-app"
    assert content =~ "servers:"
    assert content =~ "caddy:"
    assert content =~ "release:"
    assert content =~ "health_check:"
  end

  test "does not overwrite existing config", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["init"], dir)
    assert output =~ "already exists"

    # Original content preserved
    content = File.read!(Path.join(dir, "config/deploy.yml"))
    assert content =~ "test-app"
  end
end
