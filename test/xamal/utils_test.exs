defmodule Xamal.UtilsTest do
  use ExUnit.Case, async: true

  alias Xamal.Utils

  describe "shell_escape/1" do
    test "wraps value in single quotes" do
      assert Utils.shell_escape("hello") == "'hello'"
    end

    test "escapes internal single quotes" do
      assert Utils.shell_escape("it's") == "'it'\\''s'"
    end

    test "handles empty string" do
      assert Utils.shell_escape("") == "''"
    end
  end

  describe "to_release_name/1" do
    test "converts hyphens to underscores" do
      assert Utils.to_release_name("my-app") == "my_app"
    end

    test "lowercases and sanitizes" do
      assert Utils.to_release_name("My.App-Name") == "my_app_name"
    end
  end

  describe "parse_host_port/1" do
    test "parses host:port" do
      assert Utils.parse_host_port("example.com:2222") == {"example.com", 2222}
    end

    test "defaults to port 22" do
      assert Utils.parse_host_port("example.com") == {"example.com", 22}
    end

    test "accepts custom default port" do
      assert Utils.parse_host_port("example.com", 4000) == {"example.com", 4000}
    end
  end

  describe "git_dirty?/0" do
    setup do
      dir = Path.join(System.tmp_dir!(), "xamal_git_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "returns false for clean git repo", %{dir: dir} do
      System.cmd("git", ["init", "-b", "master", "--quiet"], cd: dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: dir)
      System.cmd("git", ["config", "user.name", "Test"], cd: dir)
      File.write!(Path.join(dir, "file.txt"), "hello")
      System.cmd("git", ["add", "."], cd: dir)
      System.cmd("git", ["commit", "-m", "init", "--quiet"], cd: dir, stderr_to_stdout: true)

      {result, _} = System.cmd("git", ["status", "--porcelain"], cd: dir)
      assert String.trim(result) == ""
    end

    test "returns true for repo with uncommitted changes", %{dir: dir} do
      System.cmd("git", ["init", "-b", "master", "--quiet"], cd: dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: dir)
      System.cmd("git", ["config", "user.name", "Test"], cd: dir)
      File.write!(Path.join(dir, "file.txt"), "hello")
      System.cmd("git", ["add", "."], cd: dir)
      System.cmd("git", ["commit", "-m", "init", "--quiet"], cd: dir, stderr_to_stdout: true)

      # Create an uncommitted file
      File.write!(Path.join(dir, "dirty.txt"), "dirty")

      {result, _} = System.cmd("git", ["status", "--porcelain"], cd: dir)
      assert String.trim(result) != ""
    end
  end

  describe "maybe_redact/2" do
    test "redacts sensitive keys" do
      assert Utils.maybe_redact("SECRET_KEY_BASE", "abc123") == "[REDACTED]"
      assert Utils.maybe_redact("DATABASE_PASSWORD", "secret") == "[REDACTED]"
    end

    test "does not redact non-sensitive keys" do
      assert Utils.maybe_redact("PHX_HOST", "example.com") == "example.com"
    end
  end
end
