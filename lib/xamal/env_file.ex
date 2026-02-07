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
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map_join("", fn {key, value} ->
      "#{key}=#{escape_value(value)}\n"
    end)
  end

  @doc """
  Write env file content to a path.
  """
  def write!(env, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(env))
  end

  # Escape a value for use in an env file.
  # Handles special characters, preserves non-ASCII (UTF-8).
  defp escape_value(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.chunk_by(fn c -> c <= 127 end)
    |> Enum.map_join("", fn chunk ->
      if Enum.all?(chunk, fn c -> c <= 127 end) do
        escape_ascii(List.to_string(chunk))
      else
        List.to_string(chunk)
      end
    end)
  end

  defp escape_value(value), do: escape_value(to_string(value))

  defp escape_ascii(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace("\"", "\\\"")
  end
end
