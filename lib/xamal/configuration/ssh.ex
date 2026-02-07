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
    opts = [
      user: String.to_charlist(ssh.user),
      silently_accept_hosts: true,
      user_interaction: false
    ]

    opts =
      cond do
        ssh.key_data ->
          opts ++ [key_cb: {Xamal.SSH.KeyProvider, key_data: ssh.key_data}]

        ssh.keys ->
          opts ++ [user_dir: hd(ssh.keys) |> Path.dirname() |> String.to_charlist()]

        true ->
          opts
      end

    opts = if ssh.config == false, do: opts ++ [ssh_config: :disabled], else: opts
    opts = opts ++ [connect_timeout: ssh.connect_timeout]

    opts
  end

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
