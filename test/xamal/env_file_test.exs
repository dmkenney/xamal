defmodule Xamal.EnvFileTest do
  use ExUnit.Case, async: true

  alias Xamal.EnvFile

  describe "encode/1" do
    test "generates KEY=value lines" do
      env = %{"FOO" => "bar", "BAZ" => "qux"}
      result = EnvFile.encode(env)
      assert result =~ "BAZ=qux\n"
      assert result =~ "FOO=bar\n"
    end

    test "sorts keys alphabetically" do
      env = %{"Z" => "1", "A" => "2"}
      result = EnvFile.encode(env)
      assert result == "A=2\nZ=1\n"
    end

    test "returns newline for empty map" do
      assert EnvFile.encode(%{}) == "\n"
    end

    test "escapes backslashes" do
      assert EnvFile.encode(%{"K" => "a\\b"}) == "K=a\\\\b\n"
    end

    test "escapes newlines" do
      assert EnvFile.encode(%{"K" => "line1\nline2"}) == "K=line1\\nline2\n"
    end

    test "escapes double quotes" do
      assert EnvFile.encode(%{"K" => ~s(say "hi")}) == ~s(K=say \\"hi\\"\n)
    end

    test "preserves non-ASCII characters" do
      assert EnvFile.encode(%{"K" => "café"}) == "K=café\n"
    end
  end

  describe "write!/2" do
    @tag :tmp_dir
    test "writes env file to disk", %{tmp_dir: dir} do
      path = Path.join(dir, "test.env")
      EnvFile.write!(%{"FOO" => "bar"}, path)
      assert File.read!(path) == "FOO=bar\n"
    end

    @tag :tmp_dir
    test "creates parent directories", %{tmp_dir: dir} do
      path = Path.join([dir, "a", "b", "test.env"])
      EnvFile.write!(%{"X" => "1"}, path)
      assert File.read!(path) == "X=1\n"
    end
  end
end
