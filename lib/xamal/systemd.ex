defmodule Xamal.Systemd do
  @moduledoc """
  Local systemd operations for Xamal units through `systemdkit`.

  Xamal normally executes systemd commands on remote hosts over SSH. This module
  is the local D-Bus counterpart for environments where Xamal and systemd run on
  the same host, and keeps unit naming aligned with the remote command builder.
  """

  alias Xamal.Configuration

  @type systemd_result :: :ok | {:ok, term()} | {:error, Systemd.Error.t()}

  @doc """
  Returns the systemd template instance name for a Xamal release and port.
  """
  @spec unit_instance(Configuration.t(), integer() | String.t()) :: String.t()
  def unit_instance(config, port) do
    "#{config.release.name}@#{port}"
  end

  @doc """
  Reloads the local systemd manager configuration.
  """
  @spec reload(keyword()) :: :ok | {:error, Systemd.Error.t()}
  def reload(opts \\ []), do: Systemd.reload(opts)

  @doc """
  Starts a local systemd service instance and waits for its job by default.
  """
  @spec start(Configuration.t(), integer() | String.t(), keyword()) :: systemd_result()
  def start(config, port, opts \\ []), do: Systemd.start_unit(unit_instance(config, port), opts)

  @doc """
  Stops a local systemd service instance and waits for its job by default.
  """
  @spec stop(Configuration.t(), integer() | String.t(), keyword()) :: systemd_result()
  def stop(config, port, opts \\ []), do: Systemd.stop_unit(unit_instance(config, port), opts)

  @doc """
  Enables a local systemd service instance.
  """
  @spec enable(Configuration.t(), integer() | String.t(), keyword()) ::
          {:ok, Systemd.UnitFileOperation.t()} | {:error, Systemd.Error.t()}
  def enable(config, port, opts \\ []) do
    Systemd.enable_unit_files([unit_instance(config, port)], opts)
  end

  @doc """
  Disables a local systemd service instance.
  """
  @spec disable(Configuration.t(), integer() | String.t(), keyword()) ::
          {:ok, Systemd.UnitFileOperation.t()} | {:error, Systemd.Error.t()}
  def disable(config, port, opts \\ []) do
    Systemd.disable_unit_files([unit_instance(config, port)], opts)
  end
end
