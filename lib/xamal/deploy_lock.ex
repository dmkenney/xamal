defmodule Xamal.DeployLock do
  @moduledoc false

  import Xamal.Output
  import Xamal.Remote

  alias Xamal.Commands.Lock
  alias Xamal.Context
  alias Xamal.LocalIdentity
  alias Xamal.SSH.Proxy

  @spec with_lock(Context.t(), (-> result) | (Context.t() -> result)) :: result
        when result: term()
  def with_lock(%Context{} = context, fun) when is_function(fun) do
    if context.holding_lock do
      invoke(fun, context)
    else
      acquire_lock(context)
      locked_context = Context.put_holding_lock(context, true)

      try do
        invoke(fun, locked_context)
      after
        safe_release_lock(context)
      end
    end
  end

  defp invoke(fun, context) do
    case :erlang.fun_info(fun, :arity) do
      {:arity, 1} -> fun.(context)
      {:arity, 0} -> fun.()
    end
  end

  defp acquire_lock(context) do
    config = context.config

    say("Acquiring the deploy lock...", :magenta)
    on_primary(Lock.ensure_locks_directory(config), context)

    case on_primary(lock_command(config), context) do
      {:ok, _} ->
        :ok

      {:error, {:ssh_connection_failed, hostname, port, reason}} ->
        say(
          "SSH connection failed to #{hostname}:#{port} (#{Proxy.format_reason(reason)})",
          :red
        )

        say("Verify the host is reachable and SSH is running.", :red)
        raise "SSH connection failed to #{hostname}:#{port}"

      {:error, _reason} ->
        say("Deploy lock already in place!", :red)
        print_lock_status(context)
        raise "Deploy lock found. Run 'mix xamal.lock.status' for more information"
    end
  end

  defp lock_command(config) do
    Lock.acquire(
      config,
      "Automatic deploy lock",
      config.version,
      LocalIdentity.git_user_name(),
      DateTime.utc_now() |> DateTime.to_iso8601()
    )
  end

  defp print_lock_status(context) do
    case on_primary(Lock.status(context.config), context) do
      {:ok, output} -> IO.puts(output)
      _ -> :ok
    end
  end

  defp safe_release_lock(context) do
    release_lock(context)
  rescue
    exception -> say("Error releasing deploy lock: #{Exception.message(exception)}", :red)
  end

  defp release_lock(context) do
    say("Releasing the deploy lock...", :magenta)
    on_primary(Lock.release(context.config), context)
  end
end
