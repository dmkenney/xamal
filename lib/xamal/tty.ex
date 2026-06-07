defmodule Xamal.TTY do
  @moduledoc false

  @reader_ref {:xamal_tty, :reader}

  defstruct [:backend]

  @type backend :: :auto | :otp_raw | :fd_port
  @type event :: {:data, binary()} | :eof
  @type t :: %__MODULE__{backend: term()}

  @spec start_link(keyword()) :: {:ok, t()} | {:error, term()}
  def start_link(opts \\ []) do
    owner = Keyword.get(opts, :owner, self())

    opts
    |> Keyword.get(:backend, :auto)
    |> resolve_backend()
    |> start_backend(owner)
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{backend: {:otp_raw, reader}}) do
    if Process.alive?(reader), do: Process.exit(reader, :shutdown)
    set_otp_terminal_mode(:cooked)
  end

  def close(%__MODULE__{backend: {:fd_port, port, tty, old_stty}}) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    if old_stty, do: stty(tty, [String.trim(old_stty)])
    :ok
  end

  @spec port(t()) :: port() | nil
  def port(%__MODULE__{backend: {:fd_port, port, _tty, _old_stty}}), do: port
  def port(%__MODULE__{}), do: nil

  @spec unwrap_message(t(), term()) :: event() | :unknown
  def unwrap_message(
        %__MODULE__{backend: {:otp_raw, reader}},
        {@reader_ref, message_reader, event}
      )
      when reader == message_reader,
      do: event

  def unwrap_message(
        %__MODULE__{backend: {:fd_port, port, _tty, _old_stty}},
        {message_port, {:data, data}}
      )
      when port == message_port,
      do: {:data, data}

  def unwrap_message(
        %__MODULE__{backend: {:fd_port, port, _tty, _old_stty}},
        {message_port, :eof}
      )
      when port == message_port,
      do: :eof

  def unwrap_message(%__MODULE__{}, _message), do: :unknown

  @spec otp_raw_available?() :: boolean()
  def otp_raw_available? do
    case Integer.parse(System.otp_release()) do
      {release, _suffix} -> release >= 28 and shell_start_interactive_loaded?()
      :error -> false
    end
  end

  defp shell_start_interactive_loaded? do
    case :code.ensure_loaded(:shell) do
      {:module, :shell} -> function_exported?(:shell, :start_interactive, 1)
      _ -> false
    end
  end

  defp resolve_backend(:auto), do: if(otp_raw_available?(), do: :otp_raw, else: :fd_port)
  defp resolve_backend(backend) when backend in [:otp_raw, :fd_port], do: backend

  defp resolve_backend(backend),
    do: raise(ArgumentError, "invalid TTY backend: #{inspect(backend)}")

  defp start_backend(:otp_raw, owner) do
    :ok = set_otp_terminal_mode(:raw)
    reader = spawn_link(fn -> otp_raw_read_loop(owner) end)
    {:ok, %__MODULE__{backend: {:otp_raw, reader}}}
  end

  defp start_backend(:fd_port, _owner) do
    tty = tty_device()
    old_stty = tty && stty(tty, ["-g"])
    if old_stty, do: stty(tty, ["raw", "-echo"])

    port = Port.open({:fd, 0, 2}, [:binary, :eof])
    {:ok, %__MODULE__{backend: {:fd_port, port, tty, old_stty}}}
  end

  defp set_otp_terminal_mode(mode) when mode in [:raw, :cooked] do
    case :shell.start_interactive({:noshell, mode}) do
      :ok ->
        :ok

      {:error, :already_started} ->
        raise "could not set terminal #{mode} mode: shell already started"
    end
  end

  defp otp_raw_read_loop(owner) do
    case IO.getn("", 1024) do
      :eof ->
        send(owner, {@reader_ref, self(), :eof})

      data when is_binary(data) or is_list(data) ->
        send(owner, {@reader_ref, self(), {:data, IO.iodata_to_binary(data)}})
        otp_raw_read_loop(owner)
    end
  end

  defp tty_device do
    pid = System.pid()

    Enum.find_value([0, 1, 2], fn fd ->
      case File.read_link("/proc/#{pid}/fd/#{fd}") do
        {:ok, path} -> tty?(path) && path
        _ -> nil
      end
    end) || (tty?("/dev/tty") && "/dev/tty")
  end

  defp tty?(device) do
    match?({_, 0}, System.cmd("stty", [stty_file_flag(), device, "-g"], stderr_to_stdout: true))
  rescue
    _ -> false
  end

  defp stty(nil, _args), do: nil

  defp stty(device, args) do
    case System.cmd("stty", [stty_file_flag(), device | args], stderr_to_stdout: true) do
      {output, 0} -> output
      _ -> nil
    end
  end

  defp stty_file_flag do
    case :os.type() do
      {:unix, :darwin} -> "-f"
      _ -> "-F"
    end
  end
end
