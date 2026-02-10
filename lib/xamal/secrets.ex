defmodule Xamal.Secrets do
  @moduledoc """
  Loads secrets from .xamal/secrets dotenv files.

  Supports:
  - .xamal/secrets-common (shared across destinations)
  - .xamal/secrets (or .xamal/secrets.<destination>)
  - Inline command substitution via $(...) syntax

  Command substitutions are executed in parallel for performance.
  """

  defstruct [:destination, :secrets_path, :secrets, :files]

  def new(opts \\ []) do
    destination = Keyword.get(opts, :destination)
    secrets_path = Keyword.get(opts, :secrets_path, ".xamal/secrets")

    files = secrets_filenames(secrets_path, destination)
    secrets = load_secrets(files)

    %__MODULE__{
      destination: destination,
      secrets_path: secrets_path,
      secrets: secrets,
      files: files
    }
  end

  def fetch(%__MODULE__{secrets: secrets, files: files}, key) do
    case Map.fetch(secrets, key) do
      {:ok, value} ->
        value

      :error ->
        existing = Enum.filter(files, &File.exists?/1)

        if existing == [] do
          raise "Secret '#{key}' not found, no secret files (#{Enum.join(files, ", ")}) provided"
        else
          raise "Secret '#{key}' not found in #{Enum.join(existing, ", ")}"
        end
    end
  end

  def get(%__MODULE__{secrets: secrets}, key, default \\ nil) do
    Map.get(secrets, key, default)
  end

  def has_key?(%__MODULE__{secrets: secrets}, key) do
    Map.has_key?(secrets, key)
  end

  def to_map(%__MODULE__{secrets: secrets}), do: secrets

  # Private

  defp secrets_filenames(secrets_path, nil) do
    ["#{secrets_path}-common", secrets_path]
  end

  defp secrets_filenames(secrets_path, destination) do
    ["#{secrets_path}-common", "#{secrets_path}.#{destination}"]
  end

  defp load_secrets(files) do
    # First pass: parse all files, collecting raw values (no command substitution yet)
    raw_secrets =
      files
      |> Enum.filter(&File.exists?/1)
      |> Enum.reduce(%{}, fn file, acc ->
        Map.merge(acc, parse_dotenv_raw(file))
      end)

    # Second pass: run all command substitutions in parallel
    resolve_commands_parallel(raw_secrets)
  end

  defp parse_dotenv_raw(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" -> acc
        String.starts_with?(line, "#") -> acc
        true -> parse_env_line_raw(line, acc)
      end
    end)
  end

  defp parse_env_line_raw(line, acc) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = value |> String.trim() |> unquote_value()
        Map.put(acc, key, value)

      _ ->
        acc
    end
  end

  defp resolve_commands_parallel(raw_secrets) do
    {needs_sub, plain} =
      Enum.split_with(raw_secrets, fn {_key, value} ->
        String.contains?(value, "$(")
      end)

    if needs_sub == [] do
      Map.new(plain)
    else
      resolved =
        needs_sub
        |> Task.async_stream(
          fn {key, value} -> {key, substitute_commands(value)} end,
          max_concurrency: 20,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      Map.new(plain ++ resolved)
    end
  end

  defp unquote_value(value) do
    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value |> String.slice(1..-2//1) |> unescape_double_quoted()

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        String.slice(value, 1..-2//1)

      true ->
        value
    end
  end

  defp unescape_double_quoted(value) do
    value
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
  end

  defp substitute_commands(value) do
    Regex.replace(~r/\$\(([^)]+)\)/, value, fn _full, cmd ->
      cmd = String.trim(cmd)

      case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
        {output, 0} -> String.trim(output)
        {error, _} -> raise "Command substitution failed for '#{cmd}': #{error}"
      end
    end)
  end
end
