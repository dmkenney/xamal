defmodule Xamal.Commands.Hook do
  @moduledoc """
  Hook script execution commands.

  Hooks are shell scripts in the hooks_path directory (default: .xamal/hooks).
  """

  alias Xamal.Configuration

  @doc """
  Build the command to run a hook script locally.
  """
  def run(config, hook_name) do
    [hook_file(config, hook_name)]
  end

  @doc """
  Build environment variables to pass to hook scripts.
  """
  def env(config, details \\ %{}, attrs \\ %{}) do
    service = Configuration.service(config)
    version = config.version || ""
    hosts = Configuration.all_hosts(config)
    host_names = Configuration.host_names(config)

    base = %{
      "XAMAL_SERVICE" => service,
      "XAMAL_VERSION" => version,
      "XAMAL_HOSTS" => Enum.join(hosts, ","),
      "XAMAL_HOST_NAMES" => Enum.map_join(hosts, ",", &Map.get(host_names, &1, &1)),
      "XAMAL_COMMAND" => Map.get(details, :command, ""),
      "XAMAL_SUBCOMMAND" => Map.get(details, :subcommand, ""),
      "XAMAL_DESTINATION" => config.destination || "",
      "XAMAL_ROLE" => Map.get(details, :role, ""),
      "XAMAL_RECORDED_AT" => Map.get(attrs, :recorded_at, ""),
      "XAMAL_PERFORMER" => Map.get(attrs, :performer, ""),
      "XAMAL_SERVICE_VERSION" => "#{service}@#{version}",
      "XAMAL_LOCK" => Map.get(attrs, :lock_status, "false")
    }

    Map.merge(base, Map.get(details, :extra_env, %{}))
  end

  @doc """
  Check if a hook file exists.
  """
  def hook_exists?(config, hook_name) do
    File.exists?(hook_file(config, hook_name))
  end

  defp hook_file(config, hook_name) do
    Path.join(Configuration.hooks_path(config), hook_name)
  end
end
