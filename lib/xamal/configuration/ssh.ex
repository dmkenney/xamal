defmodule Xamal.Configuration.Ssh do
  @moduledoc """
  SSH connection configuration.
  """

  defstruct user: "root",
            port: 22,
            proxy: nil,
            proxy_command: nil,
            keys_only: nil,
            keys: nil,
            key_data: nil,
            config: nil,
            log_level: :error,
            max_concurrent_starts: 30,
            pool_idle_timeout: 900,
            dns_retries: 3,
            connect_timeout: 15_000

  def new(config) when is_map(config) do
    %__MODULE__{
      user: Map.get(config, "user", "root"),
      port: Map.get(config, "port", 22),
      proxy: Map.get(config, "proxy"),
      proxy_command: Map.get(config, "proxy_command"),
      keys_only: Map.get(config, "keys_only"),
      keys: Map.get(config, "keys"),
      key_data: Map.get(config, "key_data"),
      config: Map.get(config, "config"),
      log_level: parse_log_level(Map.get(config, "log_level", "error")),
      max_concurrent_starts: Map.get(config, "max_concurrent_starts", 30),
      pool_idle_timeout: Map.get(config, "pool_idle_timeout", 900),
      dns_retries: Map.get(config, "dns_retries", 3),
      connect_timeout: Map.get(config, "connect_timeout", 15_000)
    }
  end

  def new(_), do: %__MODULE__{}

  @doc """
  Returns SSH connection options for Erlang's :ssh module.
  """
  def connect_options(%__MODULE__{} = ssh) do
    [
      user: String.to_charlist(ssh.user),
      silently_accept_hosts: true,
      user_interaction: false
    ]
    |> put_key_options(ssh)
    |> put_config_options(ssh)
    |> Keyword.put(:connect_timeout, ssh.connect_timeout)
  end

  defp put_key_options(opts, %{key_data: key_data}) when not is_nil(key_data) do
    opts ++ [key_cb: {Xamal.SSH.KeyProvider, key_data: key_data}]
  end

  defp put_key_options(opts, %{keys: keys}) when not is_nil(keys) do
    # Path.expand resolves a leading ~ — Erlang's :ssh does not, and would
    # otherwise stat a literal "~/.ssh" directory and fail with :enoent.
    user_dir = keys |> hd() |> Path.expand() |> Path.dirname() |> String.to_charlist()
    opts ++ [user_dir: user_dir]
  end

  defp put_key_options(opts, _ssh), do: opts

  defp put_config_options(opts, %{config: false}), do: opts ++ [ssh_config: :disabled]
  defp put_config_options(opts, _ssh), do: opts

  defp parse_log_level(level) when is_binary(level) do
    case String.downcase(level) do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      "fatal" -> :error
      _ -> :error
    end
  end

  defp parse_log_level(level) when is_atom(level), do: level
  defp parse_log_level(_), do: :error
end
