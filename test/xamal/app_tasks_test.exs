defmodule Xamal.AppTasksTest do
  use ExUnit.Case, async: true

  alias Xamal.AppTasks

  describe "parse_exec/1" do
    test "takes a leading -i as interactive and the rest as the command" do
      assert {[interactive: true], "iex"} = AppTasks.parse_exec(["-i", "iex"])
      assert {[interactive: true], ""} = AppTasks.parse_exec(["-i"])
    end

    test "accepts the long --interactive form" do
      assert {[interactive: true], "bin/app remote"} =
               AppTasks.parse_exec(["--interactive", "bin/app", "remote"])
    end

    test "passes a non-interactive command through verbatim" do
      assert {[], "MyApp.Release.migrate()"} =
               AppTasks.parse_exec(["MyApp.Release.migrate()"])
    end

    test "keeps dashed flags that belong to the command" do
      # The command's own flags must survive, not be parsed away as exec options.
      assert {[], "ls -la"} = AppTasks.parse_exec(["ls", "-la"])
      assert {[], "bin/app eval --bar"} = AppTasks.parse_exec(["bin/app", "eval", "--bar"])
    end
  end

  describe "removed tasks" do
    test "the redundant xamal.shell task no longer exists" do
      # xamal.shell mirrored Kamal's container shell, which has no analogue for
      # native host releases; it only duplicated xamal.iex. Guard against it
      # silently returning.
      refute Code.ensure_loaded?(Mix.Tasks.Xamal.Shell)
      refute function_exported?(AppTasks, :shell, 3)
    end

    test "xamal.iex is still present" do
      assert Code.ensure_loaded?(Mix.Tasks.Xamal.Iex)
      assert function_exported?(AppTasks, :iex, 3)
    end
  end
end
