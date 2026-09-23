defmodule Xamal.Remote do
  @moduledoc false

  alias Xamal.Commands.{Auditor, Caddy}
  alias Xamal.SSH

  @type command_parts :: [String.Chars.t()]

  @spec on_primary(command_parts(), Xamal.Context.t()) :: {:ok, String.t()} | {:error, term()}
  @spec on_hosts(command_parts(), Xamal.Context.t()) :: [{String.t(), term()}]
  @spec record_audit(String.t(), map(), Xamal.Context.t()) :: term()
  @spec read_active_port(String.t(), Xamal.Configuration.t()) :: integer() | nil
  @spec ssh_exec(String.t(), command_parts(), Xamal.Configuration.t()) ::
          {:ok, String.t()} | {:error, term()}

  def on_primary(command_parts, context) do
    config = context.config
    host = Xamal.Context.primary_host(context)
    SSH.execute_command(host, command_parts, ssh_config: config.ssh)
  end

  def on_hosts(command_parts, context) do
    config = context.config

    context
    |> Xamal.Context.hosts()
    |> SSH.on(fn host -> SSH.execute_command(host, command_parts, ssh_config: config.ssh) end)
  end

  def record_audit(message, details, context) do
    config = context.config

    if config do
      config
      |> Auditor.record(message, DateTime.utc_now() |> DateTime.to_iso8601(), details)
      |> on_primary(context)
    end
  end

  def read_active_port(host, config) do
    case SSH.execute_command(host, Caddy.read_active_port(config), ssh_config: config.ssh) do
      {:ok, port_str} -> parse_port(port_str)
      {:error, _} -> nil
    end
  end

  def ssh_exec(host, cmd, config) do
    SSH.execute_command(host, cmd, ssh_config: config.ssh)
  end

  @doc """
  Reload Caddy on a host, raising if the reload is rejected.

  Caddy reloads the system Caddyfile, which imports every app on the host, so
  an invalid Caddyfile from any of them fails the reload. Caddy then keeps its
  previous config. Carrying on (e.g. stopping the old release in a blue-green
  swap) would take the site down, so this raises instead.
  """
  def reload_caddy!(host, config) do
    case ssh_exec(host, Caddy.reload(), config) do
      {:ok, _} ->
        :ok

      {:error, {:exit_status, _, output}} ->
        raise "Caddy rejected the reload on #{host}; the previous config is still live:\n#{output}"

      {:error, reason} ->
        raise "Caddy reload failed on #{host}: #{inspect(reason)}"
    end
  end

  defp parse_port(port_str) do
    case Integer.parse(String.trim(port_str)) do
      {port, _} -> port
      :error -> nil
    end
  end
end
