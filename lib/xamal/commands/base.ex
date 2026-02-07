defmodule Xamal.Commands.Base do
  @moduledoc """
  Base module for building shell commands.

  Commands are represented as lists of string/atom parts that get joined
  with spaces when executed. Composition helpers (combine, pipe, chain, etc.)
  join multiple commands with shell operators.

  This matches Kamal's command-building pattern.
  """

  @doc """
  Join multiple commands with && (all must succeed).
  """
  def combine(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse(["&&"])
    |> List.flatten()
  end

  @doc """
  Join multiple commands with ; (run sequentially regardless of exit code).
  """
  def chain(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse([";"])
    |> List.flatten()
  end

  @doc """
  Join multiple commands with | (pipe stdout).
  """
  def pipe(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse(["|"])
    |> List.flatten()
  end

  @doc """
  Join with >> (append to file).
  """
  def append(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse([">>"])
    |> List.flatten()
  end

  @doc """
  Join with > (write/overwrite file).
  """
  def write(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse([">"])
    |> List.flatten()
  end

  @doc """
  Join with || (run second if first fails).
  """
  def any(commands) do
    commands
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse(["||"])
    |> List.flatten()
  end

  @doc """
  Wrap a command in sh -c '...' for safe subshell execution.
  """
  def shell(command_parts) when is_list(command_parts) do
    cmd_str = Enum.map_join(command_parts, " ", &to_string/1)
    escaped = String.replace(cmd_str, "'", "'\\''")
    ["sh", "-c", "'#{escaped}'"]
  end

  @doc """
  Create an xargs-prefixed command.
  """
  def xargs(command_parts) when is_list(command_parts) do
    ["xargs" | command_parts]
  end

  @doc """
  Create a mkdir -p command.
  """
  def make_directory(path) do
    ["mkdir", "-p", path]
  end

  @doc """
  Create an rm -r command.
  """
  def remove_directory(path) do
    ["rm", "-r", path]
  end

  @doc """
  Create an rm command.
  """
  def remove_file(path) do
    ["rm", path]
  end

  @doc """
  Convert command parts to a single shell string.
  """
  def to_command_string(parts) when is_list(parts) do
    Enum.map_join(parts, " ", &to_string/1)
  end
end
