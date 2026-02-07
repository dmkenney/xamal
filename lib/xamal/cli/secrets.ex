defmodule Xamal.CLI.Secrets do
  @moduledoc """
  CLI commands for managing secrets.
  """

  import Xamal.CLI.Base

  def run(subcommand, args, opts) do
    case subcommand do
      "fetch" -> fetch(args, opts)
      "extract" -> extract(args, opts)
      "print" -> print_secrets(args, opts)
      other -> say("Unknown secrets command: #{other}", :red)
    end
  end

  def fetch(args, _opts) do
    case args do
      [adapter | rest] ->
        say("Fetching secrets via #{adapter}...", :magenta)
        # Adapter-specific secret fetching
        # For now, just document the interface
        case adapter do
          "doppler" ->
            fetch_doppler(rest)

          "1password" ->
            fetch_1password(rest)

          "aws_secrets_manager" ->
            fetch_aws_sm(rest)

          "bitwarden" ->
            fetch_bitwarden(rest)

          "bitwarden_secrets_manager" ->
            fetch_bitwarden_sm(rest)

          "gcp_secret_manager" ->
            fetch_gcp_sm(rest)

          "last_pass" ->
            fetch_lastpass(rest)

          "passbolt" ->
            fetch_passbolt(rest)

          _ ->
            say("Unknown adapter: #{adapter}", :red)

            say(
              "Supported: doppler, 1password, aws_secrets_manager, bitwarden, bitwarden_secrets_manager, gcp_secret_manager, last_pass, passbolt"
            )
        end

      [] ->
        say("Usage: xamal secrets fetch <adapter> [options]", :red)
    end
  end

  def extract(args, _opts) do
    config = Xamal.Commander.config()

    case args do
      [key | _] ->
        value = Xamal.Secrets.fetch(config.secrets, key)
        IO.puts(value)

      [] ->
        say("Usage: xamal secrets extract <KEY>", :red)
    end
  end

  def print_secrets(_args, _opts) do
    config = Xamal.Commander.config()
    secrets = Xamal.Secrets.to_map(config.secrets)

    Enum.each(secrets, fn {key, value} ->
      IO.puts("#{key}=#{Xamal.Utils.maybe_redact(key, value)}")
    end)
  end

  def help do
    IO.puts("""
    Usage: xamal secrets <command>

    Commands:
      fetch ADAPTER   Fetch secrets from external adapter
      extract KEY     Extract a single secret value
      print           Print all secrets (sensitive values redacted)

    Adapters:
      1password                  1Password (op CLI)
      aws_secrets_manager        AWS Secrets Manager (aws CLI)
      bitwarden                  Bitwarden (bw CLI)
      bitwarden_secrets_manager  Bitwarden Secrets Manager (bws CLI)
      doppler                    Doppler (doppler CLI)
      gcp_secret_manager         Google Cloud Secret Manager (gcloud CLI)
      last_pass                  LastPass (lpass CLI)
      passbolt                   Passbolt (passbolt CLI)
    """)
  end

  defp fetch_doppler(args) do
    project = Enum.at(args, 0, "")
    config_name = Enum.at(args, 1, "")

    cmd = "doppler secrets download --no-file --format env -p #{project} -c #{config_name}"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} -> IO.puts(output)
      {error, _} -> say("Doppler fetch failed: #{error}", :red)
    end
  end

  defp fetch_1password(args) do
    case args do
      [vault, item, field | _] ->
        cmd = "op read op://#{vault}/#{item}/#{field}"

        case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
          {output, 0} -> IO.write(String.trim(output))
          {error, _} -> say("1Password fetch failed: #{error}", :red)
        end

      _ ->
        say("Usage: xamal secrets fetch 1password <vault> <item> <field>", :red)
    end
  end

  defp fetch_aws_sm(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [from: :string, profile: :string])
    prefix = Keyword.get(opts, :from, "")
    profile = Keyword.get(opts, :profile)

    secret_ids = Enum.map(secrets, fn s -> if prefix != "", do: "#{prefix}/#{s}", else: s end)

    if secret_ids == [] do
      say(
        "Usage: xamal secrets fetch aws_secrets_manager [--from PREFIX] [--profile PROFILE] SECRET...",
        :red
      )
    else
      id_args = Enum.flat_map(secret_ids, fn id -> ["--secret-id-list", id] end)
      profile_args = if profile, do: ["--profile", profile], else: []

      case System.cmd(
             "aws",
             ["secretsmanager", "batch-get-secret-value"] ++ id_args ++ profile_args,
             stderr_to_stdout: true
           ) do
        {output, 0} -> IO.puts(output)
        {error, _} -> say("AWS Secrets Manager fetch failed: #{error}", :red)
      end
    end
  end

  defp fetch_bitwarden(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [account: :string])
    account = Keyword.get(opts, :account)

    if account == nil do
      say("Usage: xamal secrets fetch bitwarden --account EMAIL ITEM [ITEM/FIELD]...", :red)
    else
      # Login and get session
      case System.cmd("bw", ["login", "--check"], stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        _ ->
          case System.cmd("bw", ["login", account, "--raw"], stderr_to_stdout: true) do
            {_, 0} -> :ok
            {error, _} -> say("Bitwarden login failed: #{error}", :red)
          end
      end

      case System.cmd("bw", ["unlock", "--raw"], stderr_to_stdout: true) do
        {session, 0} ->
          System.cmd("bw", ["sync", "--session", String.trim(session)], stderr_to_stdout: true)

          Enum.each(secrets, fn secret ->
            cmd = "bw get item '#{secret}' --session '#{String.trim(session)}'"

            case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
              {output, 0} -> IO.puts(output)
              {error, _} -> say("Failed to fetch '#{secret}': #{error}", :red)
            end
          end)

        {error, _} ->
          say("Bitwarden unlock failed: #{error}", :red)
      end
    end
  end

  defp fetch_bitwarden_sm(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [from: :string])
    project = Keyword.get(opts, :from)

    if secrets == [] and project == nil do
      say(
        "Usage: xamal secrets fetch bitwarden_secrets_manager [--from PROJECT] SECRET_UUID...",
        :red
      )
    else
      Enum.each(secrets, fn secret ->
        case System.cmd("bws", ["secret", "get", secret], stderr_to_stdout: true) do
          {output, 0} -> IO.puts(output)
          {error, _} -> say("Failed to fetch '#{secret}': #{error}", :red)
        end
      end)
    end
  end

  defp fetch_gcp_sm(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [account: :string, from: :string])
    account = Keyword.get(opts, :account)
    project = Keyword.get(opts, :from)

    if secrets == [] do
      say(
        "Usage: xamal secrets fetch gcp_secret_manager [--account USER] [--from PROJECT] SECRET...",
        :red
      )
    else
      impersonate = if account, do: ["--impersonate-service-account", account], else: []

      Enum.each(secrets, fn secret ->
        # Support project/secret/version format
        {proj, name, version} =
          case String.split(secret, "/") do
            [p, n, v] -> {p, n, v}
            [p, n] -> {p, n, "latest"}
            [n] -> {project, n, "latest"}
          end

        project_arg = if proj, do: ["--project", proj], else: []

        cmd_args =
          ["secrets", "versions", "access", version, "--secret", name] ++
            project_arg ++ impersonate

        case System.cmd("gcloud", cmd_args, stderr_to_stdout: true) do
          {output, 0} -> IO.puts(String.trim(output))
          {error, _} -> say("Failed to fetch '#{secret}': #{error}", :red)
        end
      end)
    end
  end

  defp fetch_lastpass(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [account: :string])
    account = Keyword.get(opts, :account)

    if account == nil do
      say("Usage: xamal secrets fetch last_pass --account EMAIL SECRET...", :red)
    else
      # Verify logged in
      case System.cmd("lpass", ["status", "--quiet"], stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        _ ->
          case System.cmd("lpass", ["login", account], stderr_to_stdout: true) do
            {_, 0} -> :ok
            {error, _} -> say("LastPass login failed: #{error}", :red)
          end
      end

      Enum.each(secrets, fn secret ->
        case System.cmd("lpass", ["show", "--json", secret], stderr_to_stdout: true) do
          {output, 0} -> IO.puts(output)
          {error, _} -> say("Failed to fetch '#{secret}': #{error}", :red)
        end
      end)
    end
  end

  defp fetch_passbolt(args) do
    {opts, secrets, _} = OptionParser.parse(args, switches: [from: :string])
    folder = Keyword.get(opts, :from)

    if secrets == [] do
      say("Usage: xamal secrets fetch passbolt [--from FOLDER] SECRET...", :red)
    else
      filter_args = if folder, do: ["--filter", "folder=#{folder}"], else: []

      Enum.each(secrets, fn secret ->
        cmd_args = ["get", "resource", "--filter", "name=#{secret}"] ++ filter_args

        case System.cmd("passbolt", cmd_args, stderr_to_stdout: true) do
          {output, 0} -> IO.puts(output)
          {error, _} -> say("Failed to fetch '#{secret}': #{error}", :red)
        end
      end)
    end
  end
end
