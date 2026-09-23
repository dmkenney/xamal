defmodule Xamal.Remove do
  @moduledoc """
  Removes remote application and Caddy resources.
  """

  import Xamal.DeployLock
  import Xamal.Output
  import Xamal.Remote
  import Xamal.TaskHelpers

  alias Xamal.AppTasks
  alias Xamal.Commands.Server, as: ServerCommand
  alias Xamal.Commands.Systemd

  def run(_args, opts, context) do
    confirming("This will remove all releases and Caddy config. Are you sure?", opts, fn ->
      config = context.config

      with_lock(context, fn context ->
        record_audit("Remove started", %{}, context)
        stop_app(opts, context)
        remove_systemd(config, context)
        remove_service_directory(config, context)
        reload_proxy(config, context)
        record_audit("Remove completed", %{}, context)
        say("Removed!", :green)
      end)
    end)
  end

  defp stop_app(opts, context) do
    say("Stopping app...", :magenta)
    AppTasks.stop([], opts, context)
  end

  defp remove_systemd(config, context) do
    say("Removing systemd units...", :magenta)
    on_hosts(Systemd.disable_all(config), context)
    on_hosts(Systemd.remove_unit(config), context)
  end

  defp remove_service_directory(config, context) do
    say("Removing service directory...", :magenta)
    on_hosts(ServerCommand.remove_service_directory(config), context)
  end

  # The service Caddyfile is gone with the service directory; reload so the
  # running Caddy drops this app's site and keeps serving the others.
  defp reload_proxy(config, context) do
    say("Reloading Caddy...", :magenta)
    context |> Xamal.Context.hosts() |> Enum.each(&reload_caddy!(&1, config))
  end
end
