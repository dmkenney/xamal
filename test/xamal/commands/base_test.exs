defmodule Xamal.Commands.BaseTest do
  use ExUnit.Case, async: true

  alias Xamal.Commands.Base

  describe "combine/1" do
    test "joins commands with &&" do
      result = Base.combine([["echo", "a"], ["echo", "b"]])
      assert result == ["echo", "a", "&&", "echo", "b"]
    end

    test "filters nil commands" do
      result = Base.combine([["echo", "a"], nil, ["echo", "b"]])
      assert result == ["echo", "a", "&&", "echo", "b"]
    end

    test "single command" do
      result = Base.combine([["echo", "a"]])
      assert result == ["echo", "a"]
    end
  end

  describe "chain/1" do
    test "joins commands with ;" do
      result = Base.chain([["echo", "a"], ["echo", "b"]])
      assert result == ["echo", "a", ";", "echo", "b"]
    end
  end

  describe "pipe/1" do
    test "joins commands with |" do
      result = Base.pipe([["ls"], ["grep", "foo"]])
      assert result == ["ls", "|", "grep", "foo"]
    end
  end

  describe "append/1" do
    test "joins with >>" do
      result = Base.append([["echo", "log"], ["file.log"]])
      assert result == ["echo", "log", ">>", "file.log"]
    end
  end

  describe "write/1" do
    test "joins with >" do
      result = Base.write([["echo", "content"], ["file.txt"]])
      assert result == ["echo", "content", ">", "file.txt"]
    end
  end

  describe "any/1" do
    test "joins with ||" do
      result = Base.any([["cmd1"], ["cmd2"]])
      assert result == ["cmd1", "||", "cmd2"]
    end
  end

  describe "shell/1" do
    test "wraps in sh -c" do
      result = Base.shell(["echo", "hello", "world"])
      assert result == ["sh", "-c", "'echo hello world'"]
    end

    test "escapes single quotes" do
      result = Base.shell(["echo", "it's"])
      assert result == ["sh", "-c", "'echo it'\\''s'"]
    end
  end

  describe "xargs/1" do
    test "prepends xargs" do
      result = Base.xargs(["docker", "stop"])
      assert result == ["xargs", "docker", "stop"]
    end
  end

  describe "make_directory/1" do
    test "creates mkdir -p command" do
      assert Base.make_directory("/opt/xamal") == ["mkdir", "-p", "/opt/xamal"]
    end
  end

  describe "remove_directory/1" do
    test "creates rm -r command" do
      assert Base.remove_directory("/opt/xamal") == ["rm", "-r", "/opt/xamal"]
    end
  end

  describe "to_command_string/1" do
    test "joins parts with spaces" do
      assert Base.to_command_string(["echo", "hello", "world"]) == "echo hello world"
    end
  end
end
