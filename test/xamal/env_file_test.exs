defmodule Xamal.EnvFileTest do
  use ExUnit.Case, async: true

  alias Xamal.EnvFile

  # Values that broke the old format or the shell: quotes, expansions,
  # command separators, newlines, and surrounding spaces.
  @nasty %{
    "QUOTES" => ~s(it's "q"),
    "EXPAND" => "$HOME ${PATH} `id` $(id)",
    "INJECT" => "pa$sword;touch /tmp/xamal-pwned",
    "BACKSLASH" => "a\\nb\\\\c\\",
    "MULTILINE" => "-----BEGIN KEY-----\nline2\n-----END KEY-----\n",
    "SPACES" => "  lead and trail  ",
    "HASH" => "# not a comment",
    "UNICODE" => "café ✓",
    "EMPTY" => ""
  }

  describe "encode/1" do
    test "writes double-quoted KEY=value lines sorted by key" do
      assert EnvFile.encode(%{"Z" => "1", "A" => "two"}) == ~s(A="two"\nZ="1"\n)
    end

    test "returns newline for empty map" do
      assert EnvFile.encode(%{}) == "\n"
    end

    test "escapes only backslash and double quote" do
      assert EnvFile.encode(%{"K" => ~S(\ " $ ` ')}) == ~S(K="\\ \" $ ` '") <> "\n"
    end

    test "keeps newlines as real newlines" do
      assert EnvFile.encode(%{"K" => "a\nb"}) == ~s(K="a\nb"\n)
    end

    test "rejects invalid names and NUL bytes without printing the value" do
      error = assert_raise ArgumentError, fn -> EnvFile.encode(%{"A;B" => "secret"}) end
      assert error.message =~ "Invalid env var name"
      refute error.message =~ "secret"

      error = assert_raise ArgumentError, fn -> EnvFile.encode(%{"K" => "sec\0ret"}) end
      assert error.message =~ "NUL"
      refute error.message =~ "sec"

      error = assert_raise ArgumentError, fn -> EnvFile.encode(%{"K" => <<"sec", 0xFF>>}) end
      assert error.message =~ "not valid UTF-8"
      refute error.message =~ "sec"
    end
  end

  describe "encode_shell/1" do
    test "writes single-quoted export lines" do
      assert EnvFile.encode_shell(%{"K" => "it's"}) == "export K='it'\\''s'\n"
    end

    @tag :tmp_dir
    test "the shell reads every value back exactly and runs nothing", %{tmp_dir: dir} do
      path = Path.join(dir, "app.sh")
      File.write!(path, EnvFile.encode_shell(@nasty))

      for {key, value} <- @nasty do
        assert {^value, 0} =
                 System.cmd("sh", ["-c", ~s(. "$1" && printf %s "$#{key}"), "sh", path])
      end

      refute File.exists?("/tmp/xamal-pwned")
    end
  end

  describe "systemd parsing" do
    @describetag :systemd
    @describetag :tmp_dir

    test "systemd reads every value back exactly", %{tmp_dir: dir} do
      path = Path.join(dir, "app.env")
      File.write!(path, EnvFile.encode(@nasty))

      {output, 0} =
        System.cmd("systemd-run", [
          "--user",
          "--quiet",
          "--pipe",
          "--wait",
          "-p",
          "EnvironmentFile=#{path}",
          "/usr/bin/env",
          "-0"
        ])

      env =
        output
        |> String.split(<<0>>, trim: true)
        |> Map.new(fn line -> line |> String.split("=", parts: 2) |> List.to_tuple() end)

      for {key, value} <- @nasty do
        assert env[key] == value, "#{key}: expected #{inspect(value)}, got #{inspect(env[key])}"
      end
    end
  end

  describe "write!/2" do
    @tag :tmp_dir
    test "writes the systemd format and creates parent directories", %{tmp_dir: dir} do
      path = Path.join([dir, "a", "b", "test.env"])
      EnvFile.write!(%{"FOO" => "bar"}, path)
      assert File.read!(path) == ~s(FOO="bar"\n)
    end
  end
end
