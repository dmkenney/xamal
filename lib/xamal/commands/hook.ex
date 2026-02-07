defmodule Xamal.Commands.Hook do
  @moduledoc """
  Hook script execution commands.

  Hooks are shell scripts in the hooks_path directory (default: .xamal/hooks).
  """

  @doc """
  Build the command to run a hook script locally.
  """
  def run(config, hook_name) do
    [hook_file(config, hook_name)]
  end

  @doc """
  Build environment variables to pass to hook scripts.
  """
  def env(config, details \\ %{}) do
    service = Xamal.Configuration.service(config)
    version = config.version || ""

    base = %{
      "XAMAL_SERVICE" => service,
      "XAMAL_VERSION" => version,
      "XAMAL_HOSTS" => Xamal.Configuration.all_hosts(config) |> Enum.join(","),
      "XAMAL_COMMAND" => Map.get(details, :command, ""),
      "XAMAL_SUBCOMMAND" => Map.get(details, :subcommand, ""),
      "XAMAL_DESTINATION" => config.destination || "",
      "XAMAL_ROLE" => Map.get(details, :role, ""),
      "XAMAL_RECORDED_AT" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "XAMAL_PERFORMER" => performer(),
      "XAMAL_SERVICE_VERSION" => "#{service}@#{version}",
      "XAMAL_LOCK" => lock_status()
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
    Path.join(Xamal.Configuration.hooks_path(config), hook_name)
  end

  defp performer do
    case System.cmd("git", ["config", "user.name"], stderr_to_stdout: true) do
      {name, 0} ->
        name = String.trim(name)

        case System.cmd("git", ["config", "user.email"], stderr_to_stdout: true) do
          {email, 0} -> "#{name} <#{String.trim(email)}>"
          _ -> name
        end

      _ ->
        case System.cmd("whoami", [], stderr_to_stdout: true) do
          {user, 0} -> String.trim(user)
          _ -> ""
        end
    end
  end

  defp lock_status do
    try do
      if Xamal.Commander.holding_lock?(), do: "true", else: "false"
    rescue
      _ -> "false"
    end
  end
end
