defmodule Xamal.CLITest do
  use ExUnit.Case

  describe "main/1" do
    test "version command outputs version" do
      output = capture_io(fn -> Xamal.CLI.main(["version"]) end)
      assert output =~ "Xamal"
      assert output =~ Xamal.version()
    end

    test "help command outputs help text" do
      output = capture_io(fn -> Xamal.CLI.main([]) end)
      assert output =~ "Usage: xamal"
      assert output =~ "deploy"
      assert output =~ "setup"
    end

    test "help command lists subcommands" do
      output = capture_io(fn -> Xamal.CLI.main([]) end)
      assert output =~ "app"
      assert output =~ "build"
      assert output =~ "lock"
      assert output =~ "prune"
      assert output =~ "secrets"
      assert output =~ "server"
    end
  end

  describe "init command" do
    @tag :tmp_dir
    test "creates config stubs", %{tmp_dir: dir} do
      # Run init from a temp directory
      original_dir = File.cwd!()

      try do
        File.cd!(dir)

        output = capture_io(fn -> Xamal.CLI.Main.init([], []) end)

        assert output =~ "Created configuration file"
        assert output =~ "Created .xamal/secrets"
        assert output =~ "Created sample hooks"

        assert File.exists?(Path.join(dir, "config/deploy.yml"))
        assert File.exists?(Path.join(dir, ".xamal/secrets"))
        assert File.exists?(Path.join(dir, ".xamal/hooks/pre-deploy"))
        assert File.exists?(Path.join(dir, ".xamal/hooks/post-deploy"))

        # Verify deploy.yml content
        content = File.read!(Path.join(dir, "config/deploy.yml"))
        assert content =~ "service: my-app"
        assert content =~ "servers:"
        assert content =~ "caddy:"
      after
        File.cd!(original_dir)
      end
    end

    @tag :tmp_dir
    test "doesn't overwrite existing config", %{tmp_dir: dir} do
      original_dir = File.cwd!()

      try do
        File.cd!(dir)
        File.mkdir_p!("config")
        File.write!("config/deploy.yml", "existing")

        output = capture_io(fn -> Xamal.CLI.Main.init([], []) end)

        assert output =~ "already exists"
        assert File.read!("config/deploy.yml") == "existing"
      after
        File.cd!(original_dir)
      end
    end
  end

  defp capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
