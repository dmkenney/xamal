defmodule Xamal.Details do
  @moduledoc """
  Prints application and proxy status for selected hosts.
  """

  import Xamal.Output
  import Xamal.Remote

  alias Xamal.Commands.App, as: AppCommand
  alias Xamal.Context
  alias Xamal.SSH

  def print(_args, _opts, context) do
    config = context.config

    Enum.each(Context.hosts(context), fn host ->
      say("Host: #{host_label(config, host)}", :magenta)
      print_host_details(host, config)
      IO.puts("")
    end)
  end

  defp print_host_details(host, config) do
    active_port = read_active_port(host, config)

    case SSH.execute_command(host, AppCommand.details(config, active_port),
           ssh_config: config.ssh
         ) do
      {:ok, output} -> IO.puts(output)
      {:error, reason} -> say("  Error: #{inspect(reason)}", :red)
    end
  end
end
