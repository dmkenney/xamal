defmodule Xamal.SSH do
  @moduledoc """
  High-level SSH API for executing commands on remote hosts.

  Provides `on/2` and `on_roles/3` for parallel execution across hosts.
  Uses Erlang's `:ssh` stdlib under the hood via ConnectionPool.
  """

  alias Xamal.SSH.{ConnectionPool, Host, Runner}

  @doc """
  Execute a function on each host in parallel.
  Returns list of {host, result} tuples.
  """
  def on(hosts, fun) when is_list(hosts) do
    Runner.run(hosts, fun)
  end

  @doc """
  Execute on hosts grouped by role, with configurable parallelism.
  """
  def on_roles(roles, config, fun, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, false)
    boot = config.boot

    if parallel and boot.parallel_roles do
      # All roles in parallel
      roles
      |> Enum.flat_map(fn role ->
        on(role.hosts, fn host -> fun.(host, role) end)
      end)
    else
      # Roles sequentially, hosts within role in parallel (with limit)
      Enum.flat_map(roles, fn role ->
        limit = Xamal.Configuration.Boot.resolved_limit(boot, length(role.hosts))

        Runner.run(role.hosts, fn host -> fun.(host, role) end,
          concurrency: limit,
          wait: boot.wait
        )
      end)
    end
  end

  @doc """
  Execute a shell command string on a remote host.
  Returns {:ok, output} or {:error, reason}.
  """
  def execute(host, command, opts \\ []) when is_binary(command) do
    ssh_config = Keyword.get(opts, :ssh_config, %Xamal.Configuration.Ssh{})
    timeout = Keyword.get(opts, :timeout, 30_000)
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    checkout_result =
      try do
        ConnectionPool.checkout(
          hostname,
          port,
          ssh_config.user,
          Xamal.Configuration.Ssh.connect_options(ssh_config)
        )
      catch
        :exit, {:timeout, _} ->
          {:error, {:ssh_connection_failed, hostname, port, :timeout}}
      end

    with {:ok, conn} <- checkout_result do
      try do
        exec_command(conn, command, timeout)
      after
        ConnectionPool.checkin(hostname, port, ssh_config.user)
      end
    end
  end

  @doc """
  Upload a file to a remote host via SCP (using SFTP channel).
  """
  def upload(host, local_path, remote_path, opts \\ []) do
    ssh_config = Keyword.get(opts, :ssh_config, %Xamal.Configuration.Ssh{})
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    checkout_result =
      try do
        ConnectionPool.checkout(
          hostname,
          port,
          ssh_config.user,
          Xamal.Configuration.Ssh.connect_options(ssh_config)
        )
      catch
        :exit, {:timeout, _} ->
          {:error, {:ssh_connection_failed, hostname, port, :timeout}}
      end

    with {:ok, conn} <- checkout_result do
      try do
        upload_via_sftp(conn, local_path, remote_path)
      after
        ConnectionPool.checkin(hostname, port, ssh_config.user)
      end
    end
  end

  @doc """
  Execute a command list (as built by Commands modules) on a host.
  Joins the command parts into a single shell string.
  """
  def execute_command(host, command_parts, opts \\ []) when is_list(command_parts) do
    command = Enum.map_join(command_parts, " ", &to_string/1)
    execute(host, command, opts)
  end

  @doc """
  Run a command interactively with a PTY (for IEx remote, bash, etc.).
  Connects local stdin/stdout to the remote session.
  """
  def interactive_exec(host, command, opts \\ []) do
    ssh_config = Keyword.get(opts, :ssh_config, %Xamal.Configuration.Ssh{})
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    with {:ok, conn} <-
           ConnectionPool.checkout(
             hostname,
             port,
             ssh_config.user,
             Xamal.Configuration.Ssh.connect_options(ssh_config)
           ) do
      try do
        do_interactive_exec(conn, command)
      after
        ConnectionPool.checkin(hostname, port, ssh_config.user)
      end
    end
  end

  @doc """
  Stream command output to stdout (for logs -f, etc.).
  Runs until the remote command exits or the process is interrupted.
  """
  def streaming_exec(host, command, opts \\ []) do
    ssh_config = Keyword.get(opts, :ssh_config, %Xamal.Configuration.Ssh{})
    timeout = Keyword.get(opts, :timeout, :infinity)
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    with {:ok, conn} <-
           ConnectionPool.checkout(
             hostname,
             port,
             ssh_config.user,
             Xamal.Configuration.Ssh.connect_options(ssh_config)
           ) do
      try do
        do_streaming_exec(conn, command, timeout)
      after
        ConnectionPool.checkin(hostname, port, ssh_config.user)
      end
    end
  end

  # Private

  defp do_interactive_exec(conn, command) do
    {:ok, channel} = :ssh_connection.session_channel(conn, 30_000)

    # Get terminal dimensions
    {cols, rows} = terminal_size()

    # Request PTY
    pty_opts = [{:term, "xterm-256color"}, {:width, cols}, {:height, rows}]
    pty_result = :ssh_connection.ptty_alloc(conn, channel, pty_opts, 30_000)
    true = pty_result in [:ok, :success]

    # Execute command
    exec_result = :ssh_connection.exec(conn, channel, String.to_charlist(command), 30_000)
    true = exec_result in [:ok, :success]

    # Save terminal state and set raw mode
    old_stty = :os.cmd(~c"stty -F /dev/tty -g") |> to_string() |> String.trim()
    :os.cmd(~c"stty -F /dev/tty raw -echo")

    # Steal fd 0 for raw keystroke reading. Uses fd 2 (stderr) as the port output fd
    # so we don't steal fd 1 from prim_tty — IO.write still works for channel output.
    stdin_port = Port.open({:fd, 0, 2}, [:binary, :eof])

    try do
      interactive_channel_loop(conn, channel, stdin_port)
    after
      try do
        Port.close(stdin_port)
      catch
        _, _ -> :ok
      end

      :os.cmd(String.to_charlist("stty -F /dev/tty #{old_stty}"))
    end
  end

  defp interactive_channel_loop(conn, channel, stdin_port) do
    receive do
      {^stdin_port, {:data, data}} ->
        :ssh_connection.send(conn, channel, data)
        interactive_channel_loop(conn, channel, stdin_port)

      {^stdin_port, :eof} ->
        :ssh_connection.send_eof(conn, channel)
        interactive_channel_loop(conn, channel, stdin_port)

      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        IO.write(data)
        interactive_channel_loop(conn, channel, stdin_port)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        interactive_channel_loop(conn, channel, stdin_port)

      {:ssh_cm, ^conn, {:exit_status, ^channel, _status}} ->
        interactive_channel_loop(conn, channel, stdin_port)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        :ok
    end
  end

  defp do_streaming_exec(conn, command, timeout) do
    {:ok, channel} = :ssh_connection.session_channel(conn, 30_000)

    exec_result = :ssh_connection.exec(conn, channel, String.to_charlist(command), 30_000)
    true = exec_result in [:ok, :success]

    streaming_loop(conn, channel, timeout)
  end

  defp streaming_loop(conn, channel, timeout) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        IO.write(data)
        streaming_loop(conn, channel, timeout)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        streaming_loop(conn, channel, timeout)

      {:ssh_cm, ^conn, {:exit_status, ^channel, _status}} ->
        streaming_loop(conn, channel, timeout)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        :ok
    after
      timeout ->
        :ssh_connection.close(conn, channel)
        {:error, :timeout}
    end
  end

  defp terminal_size do
    cols =
      case :io.columns() do
        {:ok, c} -> c
        _ -> 80
      end

    rows =
      case :io.rows() do
        {:ok, r} -> r
        _ -> 24
      end

    {cols, rows}
  end

  defp exec_command(conn, command, timeout) do
    {:ok, channel} = :ssh_connection.session_channel(conn, timeout)

    # OTP 27+ returns :success instead of :ok
    result = :ssh_connection.exec(conn, channel, String.to_charlist(command), timeout)
    true = result in [:ok, :success]

    receive_output(conn, channel, "", timeout)
  end

  defp receive_output(conn, channel, acc, timeout) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        receive_output(conn, channel, acc <> to_string(data), timeout)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        receive_output(conn, channel, acc, timeout)

      {:ssh_cm, ^conn, {:exit_status, ^channel, 0}} ->
        receive_output(conn, channel, acc, timeout)

      {:ssh_cm, ^conn, {:exit_status, ^channel, status}} ->
        :ssh_connection.close(conn, channel)
        {:error, {:exit_status, status, acc}}

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        {:ok, String.trim(acc)}
    after
      timeout ->
        :ssh_connection.close(conn, channel)
        {:error, :timeout}
    end
  end

  defp upload_via_sftp(conn, local_path, remote_path) do
    {:ok, sftp} = :ssh_sftp.start_channel(conn)

    try do
      content = File.read!(local_path)
      :ok = :ssh_sftp.write_file(sftp, String.to_charlist(remote_path), content)
      {:ok, remote_path}
    after
      :ssh_sftp.stop_channel(sftp)
    end
  end
end
