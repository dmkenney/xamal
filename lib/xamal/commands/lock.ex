defmodule Xamal.Commands.Lock do
  @moduledoc """
  Deploy lock commands using mkdir-based locking (identical to Kamal).
  """

  import Xamal.Commands.Base

  @doc """
  Acquire the deploy lock. mkdir is atomic - fails if dir exists.
  """
  def acquire(config, message, version) do
    combine([
      ["mkdir", lock_dir(config)],
      write_lock_details(config, message, version)
    ])
  end

  @doc """
  Release the deploy lock.
  """
  def release(config) do
    combine([
      remove_file(lock_details_file(config)),
      remove_directory(lock_dir(config))
    ])
  end

  @doc """
  Check lock status.
  """
  def status(config) do
    combine([
      write([["stat", lock_dir(config)], ["/dev/null"]]),
      read_lock_details(config)
    ])
  end

  @doc """
  Ensure the locks parent directory exists.
  """
  def ensure_locks_directory(_config) do
    make_directory(Xamal.Configuration.run_directory())
  end

  defp write_lock_details(config, message, version) do
    details = lock_details(message, version)
    encoded = Base.encode64(details)

    write([
      ["echo", "\"#{encoded}\""],
      [lock_details_file(config)]
    ])
  end

  defp read_lock_details(config) do
    pipe([
      ["cat", lock_details_file(config)],
      ["base64", "-d"]
    ])
  end

  defp lock_dir(config) do
    Xamal.Configuration.lock_directory(config)
  end

  defp lock_details_file(config) do
    "#{lock_dir(config)}/details"
  end

  defp lock_details(message, version) do
    locked_by = git_user_name()
    time = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    Locked by: #{locked_by} at #{time}
    Version: #{version}
    Message: #{message}\
    """
  end

  defp git_user_name do
    case System.cmd("git", ["config", "user.name"], stderr_to_stdout: true) do
      {name, 0} -> String.trim(name)
      _ -> "Unknown"
    end
  end
end
