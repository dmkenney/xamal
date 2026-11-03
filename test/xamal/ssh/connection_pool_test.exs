defmodule Xamal.SSH.ConnectionPoolTest do
  # Stops and crashes the app's shared pool.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
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

  test "follow logs and interactive exec fail loudly when the pool is down" do
    :ok = Supervisor.terminate_child(Xamal.Supervisor, ConnectionPool)
    on_exit(fn -> Supervisor.restart_child(Xamal.Supervisor, ConnectionPool) end)

    config =
      Xamal.Configuration.new(%{
        "service" => "my-app",
        "servers" => %{"web" => ["10.0.0.1"]},
        "ssh" => %{"key_data" => @key}
      })

    context = Xamal.Context.new(config)

    capture_io(fn ->
      error =
        assert_raise Mix.Error, ~r/Log stream failed on 10.0.0.1/, fn ->
          Xamal.Logs.dispatch_logs([follow: true], fn _ -> ["true"] end, config, [], context)
        end

      refute error.message =~ "PRIVATE KEY"

      assert_raise Mix.Error, ~r/Interactive command failed on 10.0.0.1/, fn ->
        Xamal.AppTasks.exec(["-i", "true"], [], context)
      end
    end)
  end

  test "an error while connecting returns an error and keeps the pool running" do
    pool = Process.whereis(ConnectionPool)

    # An unparseable proxy port raises inside connect. Configuration.new
    # rejects it, so build the options directly.
    opts = Ssh.connect_options(Ssh.new(%{"key_data" => @key, "proxy" => "bastion:x"}))

    log =
      capture_log(fn ->
        result = ConnectionPool.checkout("10.0.0.1", 22, "root", opts)

        assert {:error, {:ssh_connection_failed, "10.0.0.1", 22, reason}} = result
        assert reason =~ "ArgumentError"
        refute inspect(result) =~ "PRIVATE KEY"
      end)

    assert Process.whereis(ConnectionPool) == pool
    refute log =~ "PRIVATE KEY"
  end

  test "format_status/1 redacts the connect options in crash reports" do
    opts = Ssh.connect_options(Ssh.new(%{"key_data" => @key}))
    status = %{message: {:checkout, "10.0.0.1", 22, "root", opts}, state: %ConnectionPool{}}

    assert %{message: {:checkout, "10.0.0.1", 22, "root", :redacted}} =
             ConnectionPool.format_status(status)
  end
end
