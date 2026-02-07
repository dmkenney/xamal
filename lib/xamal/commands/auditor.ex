defmodule Xamal.Commands.Auditor do
  @moduledoc """
  Audit log commands. Appends timestamped entries to the audit log.
  """

  import Xamal.Commands.Base

  @doc """
  Record an audit log entry.
  """
  def record(config, line, details \\ %{}) do
    tags = format_tags(config, details)
    escaped = Xamal.Utils.shell_escape("#{tags} #{line}")

    combine([
      make_directory(Xamal.Configuration.run_directory()),
      append([
        ["echo", escaped],
        [audit_log_file(config)]
      ])
    ])
  end

  @doc """
  Show the last 50 lines of the audit log.
  """
  def reveal(config) do
    ["tail", "-n", "50", audit_log_file(config)]
  end

  defp audit_log_file(config) do
    Xamal.Configuration.audit_log_path(config)
  end

  defp format_tags(config, details) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    service = Xamal.Configuration.service(config)

    base = "[#{timestamp}] [#{service}]"

    extra =
      details
      |> Enum.map(fn {k, v} -> "[#{k}: #{v}]" end)
      |> Enum.join(" ")

    if extra == "", do: base, else: "#{base} #{extra}"
  end
end
