defmodule Xamal.CLI.Prune do
  @moduledoc """
  CLI command for pruning old releases.
  """

  import Xamal.CLI.Base

  def prune(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()
    keep = Xamal.Configuration.retain_releases(config)

    say("Pruning old releases (keeping #{keep})...", :magenta)

    Enum.each(hosts, fn host ->
      cmd = Xamal.Commands.Prune.releases(config)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, _} -> say("  Pruned on #{host}", :green)
        {:error, _} -> say("  Nothing to prune on #{host}", :yellow)
      end
    end)
  end
end
