defmodule Xamal.SSH.ConnectionPoolTest do
  # Stops and crashes the app's shared pool.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Xamal.Configuration.Ssh
  alias Xamal.SSH.ConnectionPool

  @key "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n"

  test "a stopped pool returns an error without the key" do
    :ok = Supervisor.terminate_child(Xamal.Supervisor, ConnectionPool)
    on_exit(fn -> Supervisor.restart_child(Xamal.Supervisor, ConnectionPool) end)

    opts = Ssh.connect_options(Ssh.new(%{"key_data" => @key}))

    log =
      capture_log(fn ->
        result = ConnectionPool.checkout("10.0.0.1", 22, "root", opts)

        assert {:error, {:ssh_connection_failed, "10.0.0.1", 22, reason}} = result
        assert reason =~ "not running"
        refute inspect(result) =~ "PRIVATE KEY"
      end)

    refute log =~ "PRIVATE KEY"
  end

  test "a crash during checkout logs no key" do
    # An unparseable proxy port raises inside handle_call.
    opts = Ssh.connect_options(Ssh.new(%{"key_data" => @key, "proxy" => "bastion:x"}))

    log =
      capture_log(fn ->
        assert {:error, {:ssh_connection_failed, "10.0.0.1", 22, _}} =
                 ConnectionPool.checkout("10.0.0.1", 22, "root", opts)

        # Let the crash report reach the logger.
        Process.sleep(100)
      end)

    assert log =~ "terminating"
    refute log =~ "PRIVATE KEY"
  end
end
