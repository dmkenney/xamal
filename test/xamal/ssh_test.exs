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

    test "sets IdentitiesOnly so agent keys don't exhaust MaxAuthTries" do
      args = Xamal.SSH.scp_args("/keys/id", "deploy", "host", 22, "local", "remote")

      assert "IdentitiesOnly=yes" in args
    end

    test "orders paths local-then-remote for an upload" do
      args =
        Xamal.SSH.scp_args("/keys/id", "deploy", "host", 22, "/local/f", "/remote/f", :upload)

      assert ["/local/f", "deploy@host:/remote/f"] == Enum.take(args, -2)
    end

    test "orders paths remote-then-local for a download" do
      args =
        Xamal.SSH.scp_args("/keys/id", "deploy", "host", 22, "/local/f", "/remote/f", :download)

      assert ["deploy@host:/remote/f", "/local/f"] == Enum.take(args, -2)
    end
  end

  describe "sftp_path/1" do
    test "drops a leading ~/ since SFTP resolves relative paths against home" do
      assert Xamal.SSH.sftp_path("~/.xamal/builds/app/x.tar.gz") == ".xamal/builds/app/x.tar.gz"
    end

    test "leaves absolute and relative paths alone" do
      assert Xamal.SSH.sftp_path("/opt/xamal/x.tar.gz") == "/opt/xamal/x.tar.gz"
      assert Xamal.SSH.sftp_path("x.tar.gz") == "x.tar.gz"
    end
  end

  describe "ssh_flags/2" do
    test "uses lowercase -p for the port, unlike scp" do
      flags = Xamal.SSH.ssh_flags(%Ssh{keys: []}, 2222)

      assert "-p" in flags
      refute "-P" in flags
      assert "2222" in flags
    end

    test "carries the non-interactive options" do
      flags = Xamal.SSH.ssh_flags(%Ssh{keys: []}, 22)

      assert "BatchMode=yes" in flags
      assert "StrictHostKeyChecking=accept-new" in flags
    end

    test "includes an identity flag when a key file exists on disk" do
      path = Path.join(System.tmp_dir!(), "xamal_ssh_flags_test_key")
      File.write!(path, "")

      try do
        flags = Xamal.SSH.ssh_flags(%Ssh{keys: [path]}, 22)
        assert ["-i", path] == Enum.take(flags, 2)
      after
        File.rm(path)
      end
    end

    test "sets IdentitiesOnly with a key file so agent keys don't exhaust MaxAuthTries" do
      path = Path.join(System.tmp_dir!(), "xamal_ssh_flags_ident_only_key")
      File.write!(path, "")

      try do
        assert "IdentitiesOnly=yes" in Xamal.SSH.ssh_flags(%Ssh{keys: [path]}, 22)
      after
        File.rm(path)
      end
    end

    test "omits the identity flag for key_data and agent flows" do
      flags = Xamal.SSH.ssh_flags(%Ssh{keys: []}, 22)

      refute "-i" in flags
    end

    test "carries no user@host destination, so callers compose their own" do
      flags = Xamal.SSH.ssh_flags(%Ssh{keys: []}, 22)

      refute Enum.any?(flags, &String.contains?(&1, "@"))
    end
  end
end
