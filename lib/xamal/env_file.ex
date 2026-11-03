defmodule Xamal.EnvFile do
  @moduledoc """
  Generates env files for deployment.

  Two formats come from the same env map:

    * `encode/1` writes systemd's `EnvironmentFile=` format, read by the
      release's unit. Values are double-quoted, so newlines, spaces, and `#`
      survive; `\\`, `"`, `$`, and `` ` `` are backslash-escaped.
    * `encode_shell/1` writes `export KEY='value'` lines for `sh` to source
      (`mix xamal.app.exec`, `mix xamal.iex`). Single quotes stop the shell
      from expanding or running anything in a value.

  Never source the systemd file from a shell: the shell would expand `$` and
  backticks inside its double quotes.
  """

  @doc """
  Generate a systemd env file from a map of key-value pairs.
  """
  def encode(env) when is_map(env) do
    encode_lines(env, fn key, value -> [key, "=\"", escape_systemd(value), "\"\n"] end)
  end

  @doc """
  Generate a shell env file of `export KEY='value'` lines.
  """
  def encode_shell(env) when is_map(env) do
    encode_lines(env, fn key, value ->
      ["export ", key, "='", String.replace(value, "'", "'\\''"), "'\n"]
    end)
  end

  @doc """
  Write a systemd env file to a path.
  """
  def write!(env, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(env))
  end

  defp encode_lines(env, _line) when map_size(env) == 0, do: "\n"

  defp encode_lines(env, line) do
    env
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} ->
      validate!(key, value)
      line.(key, value)
    end)
    |> IO.iodata_to_binary()
  end

  # Errors name the key only, never the value.
  defp validate!(key, value) do
    unless Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, key) do
      raise ArgumentError,
            "Invalid env var name #{inspect(key)}: use letters, digits, and underscores, " <>
              "not starting with a digit"
    end

    if String.contains?(value, <<0>>) do
      raise ArgumentError, "The value of env var #{key} contains a NUL byte"
    end
  end

  # Inside double quotes systemd unescapes these four and keeps every other
  # backslash. The replacements are byte-level, so non-UTF-8 values pass
  # through unchanged.
  defp escape_systemd(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end
end
