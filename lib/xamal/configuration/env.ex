defmodule Xamal.Configuration.Env do
  @moduledoc """
  Environment variable configuration.

  Handles clear (non-secret) and secret env vars.
  Secret keys are resolved from the secrets store at deploy time.
  """

  # Vars managed by systemd template units — must not appear in the env file.
  @reserved_vars ["PORT"]

  defstruct [:clear, :secret_keys, :secrets]

  def new(config, secrets) when is_map(config) do
    {clear, secret_keys} = parse_env_config(config)
    warn_reserved(clear)

    %__MODULE__{
      clear: Map.drop(clear, @reserved_vars),
      secret_keys: secret_keys,
      secrets: secrets
    }
  end

  def new(_, secrets) do
    %__MODULE__{clear: %{}, secret_keys: [], secrets: secrets}
  end

  @doc """
  Merge two Env configurations. Clear vars are merged, secret keys are unioned.
  """
  def merge(%__MODULE__{} = base, %__MODULE__{} = override) do
    %__MODULE__{
      clear: Map.merge(base.clear, override.clear),
      secret_keys: Enum.uniq(base.secret_keys ++ override.secret_keys),
      secrets: base.secrets
    }
  end

  @doc """
  Returns the full env map with secrets resolved.
  """
  def to_map(%__MODULE__{clear: clear, secret_keys: secret_keys, secrets: secrets}) do
    resolved_secrets =
      secret_keys
      |> Enum.map(fn key ->
        {env_name, secret_key} = extract_alias(key)
        {env_name, Xamal.Secrets.fetch(secrets, secret_key)}
      end)
      |> Map.new()

    Map.merge(clear, resolved_secrets)
  end

  @doc """
  Returns just the clear (non-secret) env vars.
  """
  def clear_map(%__MODULE__{clear: clear}), do: clear

  @doc """
  Returns just the secret env vars (resolved).
  """
  def secrets_map(%__MODULE__{secret_keys: secret_keys, secrets: secrets}) do
    secret_keys
    |> Enum.map(fn key ->
      {env_name, secret_key} = extract_alias(key)
      {env_name, Xamal.Secrets.fetch(secrets, secret_key)}
    end)
    |> Map.new()
  end

  @doc """
  Generate an env file string for the secret values.
  """
  def secrets_env_file(%__MODULE__{} = env) do
    Xamal.EnvFile.encode(secrets_map(env))
  end

  # Private

  defp warn_reserved(clear) do
    Enum.each(@reserved_vars, fn var ->
      if Map.has_key?(clear, var) do
        IO.puts(
          :stderr,
          "\e[33mWarning: #{var} in env.clear is ignored — it is managed by the systemd service unit\e[0m"
        )
      end
    end)
  end

  defp parse_env_config(config) do
    if Map.has_key?(config, "clear") or Map.has_key?(config, "secret") do
      clear = Map.get(config, "clear", %{}) |> stringify_values()
      secret_keys = Map.get(config, "secret", [])
      {clear, secret_keys}
    else
      # Plain key-value map (no clear/secret split)
      {stringify_values(config), []}
    end
  end

  defp stringify_values(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_values(_), do: %{}

  defp extract_alias(key) do
    case String.split(key, ":", parts: 2) do
      [env_name, secret_key] -> {env_name, secret_key}
      [key] -> {key, key}
    end
  end
end
