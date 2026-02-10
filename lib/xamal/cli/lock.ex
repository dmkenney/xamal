defmodule Xamal.CLI.Lock do
  @moduledoc """
  CLI commands for managing the deploy lock.
  """

  import Xamal.CLI.Base

  def run(subcommand, args, opts) do
    case subcommand do
      "status" -> status(args, opts)
      "acquire" -> acquire(args, opts)
      "release" -> release(args, opts)
      other -> say("Unknown lock command: #{other}", :red)
    end
  end

  def status(_args, _opts) do
    config = Xamal.Commander.config()
    cmd = Xamal.Commands.Lock.status(config)

    case on_primary(cmd) do
      {:ok, output} ->
        say("Lock is held:", :yellow)
        IO.puts(output)

      {:error, _} ->
        say("No deploy lock in place", :green)
    end
  end

  def acquire(args, _opts) do
    config = Xamal.Commander.config()

    {lock_opts, rest, _} =
      OptionParser.parse(args, switches: [message: :string], aliases: [m: :message])

    message =
      cond do
        Keyword.has_key?(lock_opts, :message) -> lock_opts[:message]
        rest != [] -> Enum.join(rest, " ")
        true -> "Manual lock"
      end

    on_primary(Xamal.Commands.Lock.ensure_locks_directory(config))
    cmd = Xamal.Commands.Lock.acquire(config, message, config.version)

    case on_primary(cmd) do
      {:ok, _} -> say("Deploy lock acquired", :green)
      {:error, _} -> say("Failed to acquire lock (already locked?)", :red)
    end
  end

  def release(_args, _opts) do
    config = Xamal.Commander.config()
    cmd = Xamal.Commands.Lock.release(config)

    case on_primary(cmd) do
      {:ok, _} -> say("Deploy lock released", :green)
      {:error, reason} ->
        say("Failed to release lock: #{inspect(reason)}", :red)
    end
  end

  def help do
    IO.puts("""
    Usage: xamal lock <command>

    Commands:
      status              Check if the deploy lock is held
      acquire [-m MSG]    Manually acquire the deploy lock
      release             Release the deploy lock
    """)
  end
end
