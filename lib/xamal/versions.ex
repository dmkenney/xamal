defmodule Xamal.Versions do
  @moduledoc """
  Lists release versions on selected hosts.
  """

  import Xamal.Output

  alias Xamal.Commands.App, as: AppCommand
  alias Xamal.Context
  alias Xamal.SSH

  def list(_args, _opts, context) do
    config = context.config
    Enum.each(Context.hosts(context), &print_versions(&1, config))
  end

  defp print_versions(host, config) do
    say("Host: #{host_label(config, host)}", :magenta)
    host_versions = host_releases(host, config)
    current = host_current_version(host, config)
    Enum.each(version_lines(host_versions, current), &IO.puts/1)
    IO.puts("")
  end

  defp host_releases(host, config) do
    case SSH.execute_command(host, AppCommand.list_releases(config), ssh_config: config.ssh) do
      {:ok, output} -> output |> String.trim() |> String.split("\n", trim: true)
      {:error, _} -> []
    end
  end

  defp host_current_version(host, config) do
    case SSH.execute_command(host, AppCommand.current_version(config), ssh_config: config.ssh) do
      {:ok, output} -> String.trim(output)
      {:error, _} -> nil
    end
  end

  defp version_lines([], _current), do: ["  (no releases)"]

  defp version_lines(releases, current) do
    Enum.map(releases, fn version ->
      marker = if version == current, do: " (current)", else: ""
      "  #{version}#{marker}"
    end)
  end
end
