defmodule Xamal.SSHTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Ssh

  describe "key_file/1 (scp-vs-sftp selection)" do
    test "returns {:ok, expanded} for an existing on-disk key (scp path)" do
      path = Path.join(System.tmp_dir!(), "xamal_key_#{System.unique_integer([:positive])}")
      File.write!(path, "fake-key")
      on_exit(fn -> File.rm(path) end)

      assert Xamal.SSH.key_file(%Ssh{keys: [path]}) == {:ok, Path.expand(path)}
    end

    test "returns the first existing key when several are configured" do
      missing = "/nonexistent/xamal/key"
      present = Path.join(System.tmp_dir!(), "xamal_key_#{System.unique_integer([:positive])}")
      File.write!(present, "fake-key")
      on_exit(fn -> File.rm(present) end)

      assert Xamal.SSH.key_file(%Ssh{keys: [missing, present]}) == {:ok, Path.expand(present)}
    end

    test "returns :none when no configured key exists on disk (sftp path)" do
      assert Xamal.SSH.key_file(%Ssh{keys: ["/nonexistent/xamal/key"]}) == :none
    end

    test "returns :none when keys is nil (sftp path)" do
      assert Xamal.SSH.key_file(%Ssh{keys: nil}) == :none
    end

    test "returns :none for key_data flows (secrets manager / agent → sftp path)" do
      assert Xamal.SSH.key_file(%Ssh{key_data: "PEM", keys: nil}) == :none
    end
  end

  describe "scp_args/6" do
    test "includes identity, port, and non-interactive options" do
      args =
        Xamal.SSH.scp_args(
          "/keys/id",
          "deploy",
          "10.0.0.1",
          2222,
          "/tmp/app.tar.gz",
          "/srv/app.tar.gz"
        )

      assert ["-i", "/keys/id"] == Enum.take(args, 2)
      assert ["-P", "2222"] == Enum.slice(args, 2, 2)
      assert "BatchMode=yes" in args
      assert "StrictHostKeyChecking=accept-new" in args
      assert "/tmp/app.tar.gz" in args
      assert "deploy@10.0.0.1:/srv/app.tar.gz" in args
    end

    test "passes the port as a string for the default port" do
      args = Xamal.SSH.scp_args("/keys/id", "deploy", "host", 22, "local", "remote")

      assert ["-P", "22"] == Enum.slice(args, 2, 2)
    end
  end
end
