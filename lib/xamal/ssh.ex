defmodule Xamal.SSH do
  @moduledoc """
  High-level SSH API for executing commands on remote hosts.

  Provides `on/2` and `on_roles/3` for parallel execution across hosts.
  Uses Erlang's `:ssh` stdlib under the hood via ConnectionPool.
  """

  alias Xamal.Configuration.{Boot, Ssh}
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
    if parallel_roles?(config.boot, opts) do
      Enum.flat_map(roles, &run_role(&1, fun))
    else
      Enum.flat_map(roles, &run_role(&1, fun, config.boot))
    end
  end

  defp parallel_roles?(boot, opts) do
    Keyword.get(opts, :parallel, false) and boot.parallel_roles
  end

  defp run_role(role, fun) do
    on(role.hosts, fn host -> fun.(host, role) end)
  end

  defp run_role(role, fun, boot) do
    Runner.run(role.hosts, fn host -> fun.(host, role) end,
      concurrency: Boot.resolved_limit(boot, length(role.hosts)),
      wait: boot.wait
    )
  end

  @doc """
  Execute a shell command string on a remote host.
  Returns {:ok, output} or {:error, reason}.
  """
  def execute(host, command, opts \\ []) when is_binary(command) do
    ssh_config = Keyword.get(opts, :ssh_config, %Ssh{})
    timeout = Keyword.get(opts, :timeout, 30_000)
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    checkout_result =
      try do
        ConnectionPool.checkout(
          hostname,
          port,
          ssh_config.user,
          Ssh.connect_options(ssh_config)
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
  Upload a file to a remote host.

  When an on-disk private key is configured (`ssh.keys`), this shells out to the
  system `scp` binary, which transfers at full link speed. Erlang's built-in
  `:ssh_sftp` writes the whole file through a small SFTP window (~100-200 KB/s in
  practice), which is pathologically slow for release tarballs (hundreds of MB) —
  a multi-minute upload becomes seconds over scp. When no key file is available
  (e.g. `key_data` from a secrets manager, or an agent), it falls back to the
  in-VM SFTP channel so those flows keep working.
  """
  def upload(host, local_path, remote_path, opts \\ []) do
    ssh_config = Keyword.get(opts, :ssh_config, %Ssh{})
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    # Use scp only when both an on-disk key and the scp binary are available.
    # A missing scp binary falls back to SFTP instead of raising :enoent, so
    # the upload still succeeds (just slower) and the contract is preserved.
    case key_file(ssh_config) do
      {:ok, key_path} ->
        if scp_available?() do
          upload_via_scp(key_path, ssh_config.user, hostname, port, local_path, remote_path)
        else
          upload_via_sftp_pooled(ssh_config, hostname, port, local_path, remote_path)
        end

      :none ->
        upload_via_sftp_pooled(ssh_config, hostname, port, local_path, remote_path)
    end
  end

  defp scp_available?, do: System.find_executable("scp") != nil

  defp upload_via_sftp_pooled(ssh_config, hostname, port, local_path, remote_path) do
    checkout_result =
      try do
        ConnectionPool.checkout(
          hostname,
          port,
          ssh_config.user,
          Ssh.connect_options(ssh_config)
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
  Resolve the first existing on-disk private key from `ssh.keys`.

  Returns `{:ok, expanded_path}` when a configured key exists on disk, or
  `:none` for `key_data`/agent flows (no usable file). This selection is what
  decides whether `upload/4` uses scp or falls back to the in-VM SFTP channel.
  """
  def key_file(%{keys: keys}) when is_list(keys) do
    Enum.find_value(keys, :none, fn k ->
      expanded = Path.expand(k)
      if File.exists?(expanded), do: {:ok, expanded}, else: false
    end)
  end

  def key_file(_), do: :none

  @doc """
  Build the argument list passed to the `scp` binary.

  Uses an arg list (not a shell string) to avoid the shell, and carries the
  non-interactive deploy flags `BatchMode=yes` and
  `StrictHostKeyChecking=accept-new`.
  """
  def scp_args(key_path, user, hostname, port, local_path, remote_path) do
    [
      "-i",
      key_path,
      "-P",
      to_string(port),
      "-o",
      "BatchMode=yes",
      "-o",
      "StrictHostKeyChecking=accept-new",
      local_path,
      "#{user}@#{hostname}:#{remote_path}"
    ]
  end

  defp upload_via_scp(key_path, user, hostname, port, local_path, remote_path) do
    args = scp_args(key_path, user, hostname, port, local_path, remote_path)

    case System.cmd("scp", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, remote_path}
      {output, code} -> {:error, {:scp_failed, code, String.trim(output)}}
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
    ssh_config = Keyword.get(opts, :ssh_config, %Ssh{})
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    with {:ok, conn} <-
           ConnectionPool.checkout(
             hostname,
             port,
             ssh_config.user,
             Ssh.connect_options(ssh_config)
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
    ssh_config = Keyword.get(opts, :ssh_config, %Ssh{})
    timeout = Keyword.get(opts, :timeout, :infinity)
    hostname = Host.hostname(host)
    port = Host.port(host, ssh_config)

    with {:ok, conn} <-
           ConnectionPool.checkout(
             hostname,
             port,
             ssh_config.user,
             Ssh.connect_options(ssh_config)
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
    true = pty_result == :success

    # Execute command
    exec_result = :ssh_connection.exec(conn, channel, String.to_charlist(command), 30_000)
    true = exec_result == :success

    case Xamal.TTY.start_link(owner: self()) do
      {:ok, tty} ->
        try do
          interactive_channel_loop(conn, channel, tty)
        after
          Xamal.TTY.close(tty)
        end

      {:error, reason} ->
        :ssh_connection.close(conn, channel)
        {:error, {:tty, reason}}
    end
  end

  defp interactive_channel_loop(conn, channel, tty) do
    receive do
      message ->
        case Xamal.TTY.unwrap_message(tty, message) do
          {:data, data} ->
            :ssh_connection.send(conn, channel, data)
            interactive_channel_loop(conn, channel, tty)

          :eof ->
            :ssh_connection.send_eof(conn, channel)
            interactive_channel_loop(conn, channel, tty)

          :unknown ->
            handle_interactive_channel_message(conn, channel, tty, message)
        end
    end
  end

  defp handle_interactive_channel_message(
         conn,
         channel,
         tty,
         {:ssh_cm, conn, {:data, channel, _type, data}}
       ) do
    IO.write(data)
    interactive_channel_loop(conn, channel, tty)
  end

  defp handle_interactive_channel_message(conn, channel, tty, {:ssh_cm, conn, {:eof, channel}}) do
    interactive_channel_loop(conn, channel, tty)
  end

  defp handle_interactive_channel_message(
         conn,
         channel,
         tty,
         {:ssh_cm, conn, {:exit_status, channel, _status}}
       ) do
    interactive_channel_loop(conn, channel, tty)
  end

  defp handle_interactive_channel_message(
         conn,
         channel,
         _tty,
         {:ssh_cm, conn, {:closed, channel}}
       ) do
    :ok
  end

  defp handle_interactive_channel_message(conn, channel, tty, _message) do
    interactive_channel_loop(conn, channel, tty)
  end

  defp do_streaming_exec(conn, command, timeout) do
    {:ok, channel} = :ssh_connection.session_channel(conn, 30_000)

    exec_result = :ssh_connection.exec(conn, channel, String.to_charlist(command), 30_000)
    true = exec_result == :success

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
    true = result == :success

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
