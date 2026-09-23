defmodule Xamal.SSH.ConnectionPool do
  @moduledoc """
  GenServer managing pooled SSH connections.

  Keys connections by {hostname, port, user}.
  Idle connections are closed after the configured timeout (default 900s).
  """

  use GenServer

  alias Xamal.SSH.Proxy

  defstruct connections: %{}, idle_timeout: 900_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def checkout(host, port, user, connect_opts \\ []) do
    GenServer.call(__MODULE__, {:checkout, host, port, user, connect_opts}, 30_000)
  end

  def checkin(host, port, user) do
    GenServer.cast(__MODULE__, {:checkin, host, port, user})
  end

  def close_all do
    GenServer.call(__MODULE__, :close_all)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    idle_timeout = Keyword.get(opts, :idle_timeout, 900_000)
    {:ok, %__MODULE__{idle_timeout: idle_timeout}}
  end

  @impl true
  def handle_call({:checkout, host, port, user, connect_opts}, _from, state) do
    key = {host, port, user}

    case Map.get(state.connections, key) do
      nil ->
        case connect(host, port, connect_opts) do
          {:ok, conn, cleanup} ->
            entry = %{conn: conn, timer: nil, cleanup: cleanup}
            connections = Map.put(state.connections, key, entry)
            {:reply, {:ok, conn}, %{state | connections: connections}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      %{conn: conn, timer: timer} = entry ->
        if timer, do: Process.cancel_timer(timer)
        connections = Map.put(state.connections, key, %{entry | timer: nil})
        {:reply, {:ok, conn}, %{state | connections: connections}}
    end
  end

  @impl true
  def handle_call(:close_all, _from, state) do
    Enum.each(state.connections, fn {_key, entry} ->
      if entry.timer, do: Process.cancel_timer(entry.timer)
      close(entry)
    end)

    {:reply, :ok, %{state | connections: %{}}}
  end

  @impl true
  def handle_cast({:checkin, host, port, user}, state) do
    key = {host, port, user}

    case Map.get(state.connections, key) do
      nil ->
        {:noreply, state}

      entry ->
        timer = Process.send_after(self(), {:idle_timeout, key}, state.idle_timeout)
        connections = Map.put(state.connections, key, %{entry | timer: timer})
        {:noreply, %{state | connections: connections}}
    end
  end

  @impl true
  def handle_info({:idle_timeout, key}, state) do
    case Map.get(state.connections, key) do
      nil ->
        {:noreply, state}

      entry ->
        close(entry)
        {:noreply, %{state | connections: Map.delete(state.connections, key)}}
    end
  end

  defp connect(host, port, connect_opts) do
    timeout = Keyword.get(connect_opts, :connect_timeout, 15_000)

    opts =
      [silently_accept_hosts: true, user_interaction: false] ++
        connect_opts

    case Proxy.connect(host, port, opts, timeout) do
      {:ok, conn, cleanup} ->
        {:ok, conn, cleanup}

      {:error, reason} ->
        {:error, {:ssh_connection_failed, host, port, reason}}
    end
  end

  # Close the target connection, then whatever its proxy opened.
  defp close(%{conn: conn, cleanup: cleanup}) do
    :ssh.close(conn)
    cleanup.()
  end
end
