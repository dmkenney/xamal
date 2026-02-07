defmodule Xamal.CLIIntegration.ErrorTest do
  use ExUnit.Case, async: true
  import Xamal.IntegrationHelpers

  setup do
    dir = setup_temp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "missing config file exits 1 with helpful message", %{dir: dir} do
    {output, 1} = xamal(["deploy"], dir)
    assert output =~ "Configuration file not found"
    assert output =~ "xamal init"
  end

  test "unknown command exits 1", %{dir: dir} do
    setup_config(dir)
    {output, 1} = xamal(["bogus"], dir)
    assert output =~ "Unknown command: bogus"
  end

  test "unknown app subcommand shows error", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["app", "bogus"], dir)
    assert output =~ "Unknown app command: bogus"
  end

  test "unknown build subcommand shows error", %{dir: dir} do
    setup_config(dir)
    {output, 0} = xamal(["build", "bogus"], dir)
    assert output =~ "Unknown build command: bogus"
  end

  test "missing custom config file exits 1", %{dir: dir} do
    {output, 1} = xamal(["config", "-c", "nonexistent.yml"], dir)
    assert output =~ "Configuration file not found"
  end
end
