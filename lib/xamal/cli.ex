defmodule Xamal.CLI do
  @moduledoc """
  CLI entry point. Parses global options, dispatches to subcommands.

  This is the main_module for the escript.
  """

  @global_switches [
    verbose: :boolean,
    quiet: :boolean,
    version: :string,
    primary: :boolean,
    hosts: :string,
    roles: :string,
    config_file: :string,
    destination: :string,
    skip_hooks: :boolean,
    skip_dirty_check: :boolean,
    confirmed: :boolean,
    help: :boolean
  ]

  @global_aliases [
    v: :verbose,
    q: :quiet,
    p: :primary,
    h: :hosts,
    r: :roles,
    c: :config_file,
    d: :destination,
    H: :skip_hooks,
    y: :confirmed
  ]

  def main(argv) do
    # Ensure the OTP application is started (for escript)
    Application.ensure_all_started(:xamal)
    Logger.configure(level: :info)

    {head_opts, args, invalid} =
      OptionParser.parse_head(argv, strict: @global_switches, aliases: @global_aliases)

    if invalid != [] do
      flags = Enum.map_join(invalid, ", ", fn {flag, _} -> flag end)
      IO.puts(:stderr, "Unknown option: #{flags}")
      System.halt(1)
    end

    # Extract command, then parse trailing global opts from the rest
    # (e.g. `xamal config -d staging` where -d comes after the command)
    {command, rest} =
      case args do
        [] -> {nil, []}
        [cmd | r] -> {cmd, r}
      end

    {tail_opts, rest, _} =
      OptionParser.parse_head(rest, switches: @global_switches, aliases: @global_aliases)

    global_opts = Keyword.merge(head_opts, tail_opts)

    if Keyword.get(global_opts, :help) do
      if command do
        dispatch_help(command, ["--help"]) || print_help()
      else
        print_help()
      end

      System.halt(0)
    end

    case command do
      nil -> print_help()
      "version" -> print_version()
      "init" -> Xamal.CLI.Main.init(rest, global_opts)
      "docs" -> Xamal.CLI.Docs.run(rest)
      _ -> dispatch(command, rest, global_opts)
    end
  rescue
    e ->
      IO.puts(:stderr, "Error: #{Exception.message(e)}")
      IO.puts(:stderr, Exception.format(:error, e, __STACKTRACE__))
      System.halt(1)
  catch
    :exit, {:timeout, {GenServer, :call, _}} ->
      IO.puts(
        :stderr,
        "Error: SSH connection timed out. Verify the host is reachable and SSH is running."
      )

      System.halt(1)

    :exit, reason ->
      IO.puts(:stderr, "Error: #{inspect(reason)}")
      System.halt(1)
  end

  defp dispatch(command, args, global_opts) do
    # Help subcommands don't need config
    if dispatch_help(command, args) do
      :ok
    else
      dispatch_with_config(command, args, global_opts)
    end
  end

  defp dispatch_help(command, args) when args in [[], ["--help"]] do
    case command do
      "app" -> Xamal.CLI.App.help()
      "build" -> Xamal.CLI.Build.help()
      "lock" -> Xamal.CLI.Lock.help()
      "secrets" -> Xamal.CLI.Secrets.help()
      "server" -> Xamal.CLI.Server.help()
      _ -> if args == ["--help"], do: print_help()
    end
  end

  defp dispatch_help(_command, _args), do: nil

  defp dispatch_with_config(command, args, global_opts) do
    # Initialize configuration
    config = init_config(global_opts)

    unless config do
      config_file = Keyword.get(global_opts, :config_file, "config/deploy.yml")
      IO.puts(:stderr, "Configuration file not found: #{config_file}")
      IO.puts(:stderr, "Run 'xamal init' to generate a configuration file.")
      System.halt(1)
    end

    # Start commander if not already running
    ensure_commander(config, global_opts)

    case command do
      "setup" -> Xamal.CLI.Main.setup(args, global_opts)
      "deploy" -> Xamal.CLI.Main.deploy(args, global_opts)
      "redeploy" -> Xamal.CLI.Main.redeploy(args, global_opts)
      "rollback" -> Xamal.CLI.Main.rollback(args, global_opts)
      "details" -> Xamal.CLI.Main.details(args, global_opts)
      "versions" -> Xamal.CLI.Main.versions(args, global_opts)
      "audit" -> Xamal.CLI.Main.audit(args, global_opts)
      "config" -> Xamal.CLI.Main.config(args, global_opts)
      "remove" -> Xamal.CLI.Main.remove(args, global_opts)
      "prune" -> Xamal.CLI.Prune.prune(args, global_opts)
      "app" -> dispatch_subcommand(Xamal.CLI.App, args, global_opts)
      "build" -> dispatch_subcommand(Xamal.CLI.Build, args, global_opts)
      "lock" -> dispatch_subcommand(Xamal.CLI.Lock, args, global_opts)
      "secrets" -> dispatch_subcommand(Xamal.CLI.Secrets, args, global_opts)
      "server" -> dispatch_subcommand(Xamal.CLI.Server, args, global_opts)
      other -> check_alias(other, args, global_opts)
    end
  end

  defp dispatch_subcommand(module, args, global_opts) do
    case args do
      [] -> module.help()
      [sub | rest] -> module.run(sub, rest, global_opts)
    end
  end

  defp check_alias(command, args, global_opts) do
    config = Xamal.Commander.config()
    aliases = if config, do: config.aliases || %{}, else: %{}

    case Map.get(aliases, command) do
      nil ->
        IO.puts(:stderr, "Unknown command: #{command}. Run 'xamal --help' for usage.")
        System.halt(1)

      alias_cmd ->
        # Dispatch directly to avoid re-parsing global options,
        # which would strip subcommand-specific flags like -i
        alias_argv = OptionParser.split(alias_cmd) ++ args

        case alias_argv do
          [cmd | rest] -> dispatch(cmd, rest, global_opts)
          [] -> :ok
        end
    end
  end

  defp init_config(global_opts) do
    config_file = Keyword.get(global_opts, :config_file, "config/deploy.yml")
    destination = Keyword.get(global_opts, :destination)
    version = Keyword.get(global_opts, :version)

    # For init command, config may not exist yet
    if File.exists?(config_file) do
      Xamal.Configuration.create_from(
        config_file: config_file,
        destination: destination,
        version: version
      )
    else
      nil
    end
  end

  defp ensure_commander(config, global_opts) do
    unless Xamal.Commander.configured?() do
      if config do
        Xamal.Commander.configure(config)
      end

      if Keyword.get(global_opts, :hosts) do
        hosts = global_opts[:hosts] |> String.split(",")
        Xamal.Commander.set_specific_hosts(hosts)
      end

      if Keyword.get(global_opts, :roles) do
        roles = global_opts[:roles] |> String.split(",")
        Xamal.Commander.set_specific_roles(roles)
      end

      if Keyword.get(global_opts, :primary) do
        config = Xamal.Commander.config()

        if config do
          primary = Xamal.Configuration.primary_host(config)
          if primary, do: Xamal.Commander.set_specific_hosts([primary])
        end
      end

      cond do
        Keyword.get(global_opts, :verbose) ->
          Xamal.Commander.set_verbosity(:debug)
          Logger.configure(level: :debug)

        Keyword.get(global_opts, :quiet) ->
          Xamal.Commander.set_verbosity(:error)
          Logger.configure(level: :error)

        true ->
          :ok
      end
    end
  end

  defp print_version do
    IO.puts("Xamal #{Xamal.version()}")
  end

  defp print_help do
    IO.puts("""
    Xamal - Deploy Elixir releases to bare metal servers

    Usage: xamal <command> [options]

    Commands:
      setup               Setup servers and deploy
      deploy              Deploy app to servers
      redeploy            Deploy without bootstrapping
      rollback [VERSION]  Rollback to a previous version
      versions            List release versions on servers
      details             Show app and caddy status
      audit               Show audit log
      config              Show merged config
      init                Generate config stubs
      docs [TOPIC]        Show configuration documentation
      version             Show xamal version
      prune               Remove old releases
      remove              Remove everything from servers

    Subcommands:
      app                 Manage application (boot, start, stop, exec, logs)
      build               Build and distribute releases
      lock                Manage deploy lock
      secrets             Manage secrets
      server              Server management (exec, bootstrap, logs)

    Global options:
      -v, --verbose       Detailed logging
      -q, --quiet         Minimal logging
      -p, --primary       Run only on primary host
      -h, --hosts HOSTS   Run on specific hosts (comma-separated)
      -r, --roles ROLES   Run on specific roles (comma-separated)
      -c, --config-file   Path to config file (default: config/deploy.yml)
      -d, --destination   Destination (staging, production, etc.)
      -H, --skip-hooks    Skip hook scripts
      --skip-dirty-check  Allow deploy with uncommitted changes
      -y, --confirmed     Skip confirmation prompts
    """)
  end
end
