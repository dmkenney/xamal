defmodule Xamal.Utils do
  @moduledoc """
  Shell escaping, sensitive value redaction, and general utilities.
  """

  @sensitive_pattern ~r/(_TOKEN|_SECRET|_KEY|PASSWORD|CREDENTIALS|_AUTH)/i

  @doc """
  Escape a value for safe use in shell commands.
  Uses single-quoting with internal single quotes escaped.
  """
  def shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end

  def shell_escape(value), do: shell_escape(to_string(value))

  @doc """
  Redact sensitive values from a string for display.
  Replaces values of env vars matching sensitive patterns with [REDACTED].
  """
  def redact_sensitive(text) when is_binary(text) do
    Regex.replace(~r/([A-Z_]+=)(.+)/, text, fn _full, key, value ->
      if Regex.match?(@sensitive_pattern, key) do
        key <> "[REDACTED]"
      else
        key <> value
      end
    end)
  end

  @doc """
  Convert a service name to a valid release/app name (underscored).
  """
  def to_release_name(service) when is_binary(service) do
    service
    |> String.replace(~r/[^a-zA-Z0-9]/, "_")
    |> String.downcase()
  end

  @doc """
  Check if the git working tree has uncommitted or staged changes.
  """
  def git_dirty? do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  @doc """
  Generate a short git SHA for versioning.
  """
  def git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  @doc """
  Generate a version string from git.
  Uses git SHA, falls back to timestamp.
  """
  def version_from_git do
    case git_sha() do
      "unknown" ->
        DateTime.utc_now()
        |> Calendar.strftime("%Y%m%d%H%M%S")

      sha ->
        sha
    end
  end

  @doc """
  Optionally mask a value if it matches a sensitive env var name.
  """
  def maybe_redact(name, value) do
    if Regex.match?(@sensitive_pattern, name) do
      "[REDACTED]"
    else
      value
    end
  end

  @doc """
  Build an env var assignment string: KEY=value (shell-escaped).
  """
  def env_assignment(key, value) do
    "#{key}=#{shell_escape(value)}"
  end

  @doc """
  Parse a "host:port" string or just "host" into {host, port}.
  """
  def parse_host_port(str, default_port \\ 22) do
    case String.split(str, ":", parts: 2) do
      [host, port] ->
        case Integer.parse(port) do
          {p, ""} -> {host, p}
          _ -> {str, default_port}
        end

      [host] ->
        {host, default_port}
    end
  end
end
