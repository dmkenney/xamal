defmodule Xamal.SSH.WriteFileTest do
  # Uses the app's shared connection pool.
  use ExUnit.Case, async: false

  alias Xamal.Configuration.Ssh

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup %{tmp_dir: dir} do
    system_dir = Path.join(dir, "system")
    root = Path.join(dir, "root")
    File.mkdir_p!(system_dir)
    File.mkdir_p!(Path.join(root, "env"))

    {_, 0} =
      System.cmd("ssh-keygen", [
        "-q",
        "-t",
        "ecdsa",
        "-m",
        "PEM",
        "-N",
        "",
        "-f",
        Path.join(system_dir, "ssh_host_ecdsa_key")
      ])

    client_key = Path.join(dir, "client_key")
    {_, 0} = System.cmd("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", client_key])

    {:ok, daemon} =
      :ssh.daemon({127, 0, 0, 1}, 0,
        system_dir: String.to_charlist(system_dir),
        no_auth_needed: true,
        subsystems: [:ssh_sftpd.subsystem_spec(root: String.to_charlist(root))]
      )

    on_exit(fn -> :ssh.stop_daemon(daemon) end)
    {:ok, info} = :ssh.daemon_info(daemon)

    ssh =
      Ssh.new(%{
        "user" => "deploy",
        "port" => Keyword.fetch!(info, :port),
        "key_data" => File.read!(client_key)
      })

    %{root: root, ssh: ssh}
  end

  test "writes content over SFTP, not on a command line", %{root: root, ssh: ssh} do
    content = "SECRET_KEY_BASE=it's \"quoted\"\n"

    assert {:ok, "/env/web.env"} =
             Xamal.SSH.write_file("127.0.0.1", content, "/env/web.env", ssh_config: ssh)

    assert File.read!(Path.join(root, "env/web.env")) == content
  end
end
