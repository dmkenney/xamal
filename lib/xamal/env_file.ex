defmodule Xamal.EnvFile do
  @moduledoc """
  Generates env files for deployment.

  Encodes an env map as KEY=value lines with proper escaping.
  Compatible with Kamal's env file format.
  """

  @doc """
  Generate env file content from a map of key-value pairs.
  Returns a string with one KEY=value per line.
  """
  def encode(env) when map_size(env) == 0, do: "\n"

  def encode(env) when is_map(env) do
    env
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [to_string(key), "=", escape_value(value), "\n"] end)
    |> IO.iodata_to_binary()
  end

  @doc """
  Write env file content to a path.
  """
  def write!(env, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(env))
  end

  # Escape a value for use in an env file. Works on bytes: the escaped
  # characters are all ASCII, and UTF-8 multibyte sequences never contain
  # ASCII bytes, so non-ASCII text passes through unchanged. Non-UTF-8 values
  # pass through too, instead of raising an error that prints the value.
  defp escape_value(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace("\"", "\\\"")
  end

  defp escape_value(value), do: escape_value(to_string(value))
end
