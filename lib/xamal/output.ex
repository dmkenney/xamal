defmodule Xamal.Output do
  @moduledoc false

  alias IO.ANSI

  def say(message, color \\ :default) do
    message
    |> colorize(color)
    |> IO.puts()
  end

  defdelegate host_label(config, host), to: Xamal.Configuration

  def puts_by_host(host, output, opts \\ []) do
    type = Keyword.get(opts, :type, "App")
    quiet = Keyword.get(opts, :quiet, false)

    unless quiet do
      say("#{type} Host: #{host}")
    end

    IO.puts("#{output}\n")
  end

  defp colorize(message, :default), do: message
  defp colorize(message, color), do: ANSI.format([color, message], true)
end
