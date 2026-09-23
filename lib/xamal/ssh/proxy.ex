defmodule Xamal.SSH.Proxy do
  @moduledoc """
  Opens Erlang `:ssh` connections directly, through a jump host (`ssh.proxy`),
  or through a proxy command (`ssh.proxy_command`).

  Erlang's `:ssh` can only connect to a TCP address, so both proxy modes end
  with a connection to a local port:

  - **Jump host:** connect to the jump host, then forward a local port to the
    target with `:ssh.tcpip_tunnel_to_server/6` (the equivalent of `ssh -L`).
  - **Proxy command:** accept one local TCP connection and relay its bytes to
    and from the command's stdin/stdout, like OpenSSH's `ProxyCommand`.

  `connect/4` returns a cleanup function that closes whatever the proxy
  opened (the jump connection or the command); the caller runs it after
  closing the target connection.
  """

  @loopback ~c"127.0.0.1"

  @doc """
  Connect to `host:port`. `opts` are `:ssh.connect/4` options plus, optionally,
  `:xamal_proxy` (`"[user@]host[:port]"`) or `:xamal_proxy_command` (a shell
  command with `%h`, `%p`, `%r` placeholders).
  """
  def connect(host, port, opts, timeout) do
    {proxy, opts} = Keyword.pop(opts, :xamal_proxy)
    {proxy_command, opts} = Keyword.pop(opts, :xamal_proxy_command)

    cond do
      proxy -> via_jump_host(host, port, proxy, opts, timeout)
      proxy_command -> via_command(host, port, proxy_command, opts, timeout)
      true -> direct(host, port, opts, timeout)
    end
  end

  defp direct(host, port, opts, timeout) do
    with {:ok, conn} <- :ssh.connect(to_charlist(host), port, opts, timeout) do
      {:ok, conn, fn -> :ok end}
    end
  end

  defp via_jump_host(host, port, proxy, opts, timeout) do
    {jump_user, jump_host, jump_port} = parse_proxy(proxy, opts)
    jump_opts = Keyword.put(opts, :user, to_charlist(jump_user))

    with {:ok, jump} <- :ssh.connect(to_charlist(jump_host), jump_port, jump_opts, timeout),
         {:ok, local_port} <- tunnel(jump, host, port, timeout),
         {:ok, conn} <- connect_local(local_port, opts, timeout, fn -> :ssh.close(jump) end) do
      {:ok, conn, fn -> :ssh.close(jump) end}
    else
      {:error, reason} -> {:error, "via jump host #{proxy}: #{format_reason(reason)}"}
    end
  end

  defp tunnel(jump, host, port, timeout) do
    case :ssh.tcpip_tunnel_to_server(jump, @loopback, 0, to_charlist(host), port, timeout) do
      {:ok, local_port} ->
        {:ok, local_port}

      {:error, reason} ->
        :ssh.close(jump)
        {:error, reason}
    end
  end

  defp via_command(host, port, command, opts, timeout) do
    user = opts |> Keyword.get(:user, ~c"") |> to_string()
    command = expand_command(command, host, port, user)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, local_port} = :inet.port(listen)
    bridge = spawn(fn -> bridge(listen, command) end)
    :ok = :gen_tcp.controlling_process(listen, bridge)
    stop = fn -> send(bridge, :stop) end

    case connect_local(local_port, opts, timeout, stop) do
      {:ok, conn} -> {:ok, conn, stop}
      {:error, reason} -> {:error, "via proxy command `#{command}`: #{format_reason(reason)}"}
    end
  end

  # The target's host key is checked on this connection, but it's recorded
  # against 127.0.0.1:<random port>, so don't save it to known_hosts.
  #
  # The first tunnel opened on a fresh jump connection can drop the target's
  # SSH banner if we connect immediately, and :ssh.connect then waits for it
  # until the timeout. A short pause avoids that (20ms was enough in testing);
  # retrying covers slower links.
  @settle_ms 100
  @attempts 3

  defp connect_local(local_port, opts, timeout, on_error) do
    opts = Keyword.put(opts, :save_accepted_host, false)
    Process.sleep(@settle_ms)

    case attempt_local(local_port, opts, max(div(timeout, @attempts), 1_000), @attempts) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        on_error.()
        {:error, reason}
    end
  end

  defp attempt_local(local_port, opts, timeout, attempts_left) do
    case :ssh.connect(@loopback, local_port, opts, timeout) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, _} when attempts_left > 1 ->
        attempt_local(local_port, opts, timeout, attempts_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # :ssh reports errors as atoms, charlists, or strings.
  defp format_reason(reason) when is_list(reason), do: to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  @doc """
  Split `"[user@]host[:port]"` into `{user, host, port}`. The user defaults to
  the connection's `:user` option and the port to 22.
  """
  def parse_proxy(proxy, opts) do
    default_user = opts |> Keyword.get(:user, ~c"root") |> to_string()

    {user, host_port} =
      case String.split(proxy, "@", parts: 2) do
        [user, rest] -> {user, rest}
        [rest] -> {default_user, rest}
      end

    case String.split(host_port, ":", parts: 2) do
      [host, port] -> {user, host, String.to_integer(port)}
      [host] -> {user, host, 22}
    end
  end

  @doc """
  Expand OpenSSH `ProxyCommand` tokens: `%h` host, `%p` port, `%r` user,
  `%%` a literal `%`.
  """
  def expand_command(command, host, port, user) do
    command
    |> String.replace("%h", to_string(host))
    |> String.replace("%p", to_string(port))
    |> String.replace("%r", user)
    |> String.replace("%%", "%")
  end

  # Relay between the single :ssh connection and the command's stdio, then
  # tear both down when either side closes or the pool asks us to stop.
  defp bridge(listen, command) do
    case :gen_tcp.accept(listen, 30_000) do
      {:ok, socket} ->
        :gen_tcp.close(listen)
        port = Port.open({:spawn, command}, [:binary, :exit_status, :stream])
        :ok = :inet.setopts(socket, active: true)
        relay(socket, port)

      {:error, _} ->
        :gen_tcp.close(listen)
    end
  end

  defp relay(socket, port) do
    receive do
      {:tcp, ^socket, data} ->
        Port.command(port, data)
        relay(socket, port)

      {^port, {:data, data}} ->
        :gen_tcp.send(socket, data)
        relay(socket, port)

      {^port, {:exit_status, _}} ->
        :gen_tcp.close(socket)

      {:tcp_closed, ^socket} ->
        close_port(port)

      :stop ->
        :gen_tcp.close(socket)
        close_port(port)
    end
  end

  # Closing the port only closes the command's stdin; kill it too in case it
  # doesn't exit on EOF.
  defp close_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        Port.close(port)
        System.cmd("kill", [to_string(os_pid)], stderr_to_stdout: true)

      nil ->
        :ok
    end
  end
end
