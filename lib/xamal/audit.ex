defmodule Xamal.Audit do
  @moduledoc """
  Prints the remote deployment audit log for selected hosts.
  """

  import Xamal.Output

  alias Xamal.Commands.Auditor
  alias Xamal.Context
  alias Xamal.SSH

  def print(_args, _opts, context) do
    config = context.config

    Enum.each(Context.hosts(context), fn host ->
      case SSH.execute_command(host, Auditor.reveal(config), ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host_label(config, host), output)
        {:error, _} -> puts_by_host(host_label(config, host), "(no audit log)")
      end
    end)
  end
end
