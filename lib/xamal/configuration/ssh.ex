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
    |> put_proxy_options(ssh)
    |> Keyword.put(:connect_timeout, ssh.connect_timeout)
  end

  defp put_key_options(opts, %{key_data: key_data}) when not is_nil(key_data) do
    opts ++ [key_cb: {Xamal.SSH.KeyProvider, key_data: key_data}]
  end

  # Load the configured key file itself. Pointing :ssh at the key's directory
  # (user_dir) only finds standard names like id_ed25519, so a key called
  # deploy_key was silently ignored.
  defp put_key_options(opts, %{keys: keys} = ssh) when is_list(keys) do
    case key_file(ssh) do
      {:ok, path} -> opts ++ [key_cb: {Xamal.SSH.KeyProvider, key_data: File.read!(path)}]
      :none -> opts
    end
  end

  defp put_key_options(opts, _ssh), do: opts

  @doc """
  The first configured key in `ssh.keys` that exists on disk, as
  `{:ok, expanded_path}`, or `:none`.
  """
  def key_file(%{keys: keys}) when is_list(keys) do
    Enum.find_value(keys, :none, fn k ->
      expanded = Path.expand(k)
      if File.exists?(expanded), do: {:ok, expanded}, else: false
    end)
  end

  def key_file(_), do: :none

  # Consumed by Xamal.SSH.Proxy before the options reach :ssh.connect/4.
  defp put_proxy_options(opts, %{proxy: proxy}) when is_binary(proxy),
    do: opts ++ [xamal_proxy: proxy]

  defp put_proxy_options(opts, %{proxy_command: command}) when is_binary(command),
    do: opts ++ [xamal_proxy_command: command]

  defp put_proxy_options(opts, _ssh), do: opts

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
