defmodule Xamal.Prune do
  @moduledoc """
  Prunes old releases on selected hosts.
  """

  import Xamal.Output

  alias Xamal.Commands.Prune, as: PruneCommand
  alias Xamal.Configuration
  alias Xamal.{Context, SSH}

  def prune(_args, _opts, context) do
    config = context.config
    hosts = Context.hosts(context)
    keep = Configuration.retain_releases(config)

    say("Pruning old releases (keeping #{keep})...", :magenta)

    Enum.each(hosts, fn host ->
      cmd = PruneCommand.releases(config)

      case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, _} -> say("  Pruned on #{host_label(config, host)}", :green)
        {:error, _} -> say("  Nothing to prune on #{host_label(config, host)}", :yellow)
      end
    end)
  end
end
