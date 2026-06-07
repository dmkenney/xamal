defmodule Xamal.MixTaskTest do
  use ExUnit.Case, async: true

  alias Xamal.MixTask

  describe "parse_global_options/1 — leading task flags" do
    test "forwards a leading short task flag instead of rejecting it" do
      assert {[], ["-f"]} = MixTask.parse_global_options(["-f"])
    end

    test "forwards a leading long task flag" do
      assert {[], ["--follow"]} = MixTask.parse_global_options(["--follow"])
    end

    test "forwards a value-taking task flag and its value" do
      assert {[], ["-n", "100"]} = MixTask.parse_global_options(["-n", "100"])
      assert {[], ["--since", "10m"]} = MixTask.parse_global_options(["--since", "10m"])
      assert {[], ["--grep", "error"]} = MixTask.parse_global_options(["--grep", "error"])
    end

    test "forwards several task flags together" do
      assert {[], ["-f", "-n", "100"]} = MixTask.parse_global_options(["-f", "-n", "100"])
    end
  end

  describe "parse_global_options/1 — globals interspersed with task flags" do
    test "parses a global before a task flag" do
      assert {[verbose: true], ["--follow"]} =
               MixTask.parse_global_options(["-v", "--follow"])
    end

    test "parses a global appearing after a task flag" do
      assert {[verbose: true], ["-f"]} = MixTask.parse_global_options(["-f", "-v"])
    end

    test "parses globals on both sides of task flags" do
      assert {opts, ["--follow", "-n", "100"]} =
               MixTask.parse_global_options(["-v", "--follow", "-n", "100"])

      assert opts == [verbose: true]
    end

    test "clustered short globals are each recognized" do
      assert {opts, ["-n", "50"]} = MixTask.parse_global_options(["-v", "-q", "-n", "50"])
      assert opts == [verbose: true, quiet: true]
    end
  end

  describe "parse_global_options/1 — value-taking globals" do
    test "consumes the following token as the global's value" do
      assert {[destination: "prod"], ["-f"]} =
               MixTask.parse_global_options(["-d", "prod", "-f"])

      assert {[destination: "prod"], ["-f"]} =
               MixTask.parse_global_options(["--destination", "prod", "-f"])
    end

    test "supports the --flag=value inline form" do
      assert {[destination: "prod"], ["-f"]} =
               MixTask.parse_global_options(["--destination=prod", "-f"])
    end

    test "does not swallow the next token when the value-global is last" do
      assert {[hosts: "web1"], []} = MixTask.parse_global_options(["--hosts", "web1"])
    end
  end

  describe "parse_global_options/1 — remote-command passthrough" do
    test "does not steal flags from a remote command's argv" do
      # The command's own `-h /` must not be parsed as the global `--hosts /`.
      assert {[], ["df", "-h", "/"]} = MixTask.parse_global_options(["df", "-h", "/"])

      assert {[], ["ls", "-d", "/tmp"]} = MixTask.parse_global_options(["ls", "-d", "/tmp"])

      assert {[], ["psql", "-c", "select 1"]} =
               MixTask.parse_global_options(["psql", "-c", "select 1"])
    end

    test "stops scanning for globals at the first positional" do
      # `-p` after the command stays with the task, not parsed as --primary.
      assert {[], ["echo", "-p"]} = MixTask.parse_global_options(["echo", "-p"])
    end

    test "still parses globals that precede the command" do
      assert {[destination: "prod"], ["df", "-h", "/"]} =
               MixTask.parse_global_options(["-d", "prod", "df", "-h", "/"])

      assert {[verbose: true], ["bin/app", "remote"]} =
               MixTask.parse_global_options(["-v", "bin/app", "remote"])
    end

    test "treats a global appearing after a positional as the task's (matches old escript)" do
      assert {[], ["abc123", "-d", "prod"]} =
               MixTask.parse_global_options(["abc123", "-d", "prod"])

      assert {[destination: "prod"], ["abc123"]} =
               MixTask.parse_global_options(["-d", "prod", "abc123"])
    end
  end

  describe "parse_global_options/1 — edge cases" do
    test "preserves duplicate task flags" do
      assert {[], ["-f", "-f"]} = MixTask.parse_global_options(["-f", "-f"])
    end

    test "passes everything after `--` through untouched" do
      assert {[], ["--", "-f"]} = MixTask.parse_global_options(["--", "-f"])

      assert {[destination: "prod"], ["--", "--weird-task-flag"]} =
               MixTask.parse_global_options(["-d", "prod", "--", "--weird-task-flag"])
    end

    test "leaves plain positionals alone" do
      assert {[], ["plain", "positional"]} =
               MixTask.parse_global_options(["plain", "positional"])
    end

    test "handles empty args" do
      assert {[], []} = MixTask.parse_global_options([])
    end
  end
end
