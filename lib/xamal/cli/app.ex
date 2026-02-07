defmodule Xamal.CLI.App do
  @moduledoc """
  CLI commands for managing the application.
  """

  import Xamal.CLI.Base

  def run(subcommand, args, opts) do
    case subcommand do
      "boot" -> boot(args, opts)
      "start" -> start(args, opts)
      "stop" -> stop(args, opts)
      "exec" -> exec(args, opts)
      "logs" -> logs(args, opts)
      "details" -> details(args, opts)
      "version" -> version(args, opts)
      "remove" -> remove(args, opts)
      "releases" -> releases(args, opts)
      "stale_releases" -> stale_releases(args, opts)
      "maintenance" -> maintenance(args, opts)
      "live" -> live(args, opts)
      other -> say("Unknown app command: #{other}", :red)
    end
  end

  def boot(_args, opts) do
    config = Xamal.Commander.config()
    roles = Xamal.Commander.roles()
    app_port = config.caddy.app_port
    alt_port = Xamal.Configuration.Caddy.alt_port(config.caddy)

    boot_config = config.boot
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    run_hook("pre-app-boot", skip_hooks: skip_hooks)

    Enum.each(roles, fn role ->
      limit = Xamal.Configuration.Boot.resolved_limit(boot_config, length(role.hosts))
      wait = boot_config.wait

      hosts_batches =
        if limit do
          Enum.chunk_every(role.hosts, limit)
        else
          [role.hosts]
        end

      Enum.with_index(hosts_batches, fn batch, idx ->
        if idx > 0 and wait do
          say("  Waiting #{wait}s before next batch...", :magenta)
          Process.sleep(wait * 1000)
        end

        Enum.each(batch, fn host ->
          say("  Booting #{role.name} on #{host}...", :magenta)
          do_boot_host(config, role, host, app_port, alt_port, skip_hooks)
        end)
      end)
    end)

    run_hook("post-app-boot", skip_hooks: skip_hooks)
  end

  def start(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      active_port = read_active_port(host, config) || config.caddy.app_port
      say("  Starting on #{host} (port #{active_port})...", :magenta)
      cmd = Xamal.Commands.Systemd.start(config, active_port)
      execute_on(host, cmd, config)
    end)
  end

  def stop(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      say("  Stopping on #{host}...", :magenta)
      cmd = Xamal.Commands.Systemd.stop_all(config)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, _} -> say("  Stopped on #{host}", :green)
        {:error, _} -> say("  App not running on #{host}", :yellow)
      end
    end)
  end

  def exec(args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    {exec_opts, cmd_args, _} =
      OptionParser.parse(args, switches: [interactive: :boolean], aliases: [i: :interactive])

    command = Enum.join(cmd_args, " ")
    interactive = Keyword.get(exec_opts, :interactive, false)

    if interactive do
      # Interactive: run on first host only via native Erlang SSH
      host = hd(hosts)
      active_port = read_active_port(host, config)
      cmd = Xamal.Commands.App.exec(config, command, interactive: true, port: active_port)
      cmd_str = Xamal.Commands.Base.to_command_string(cmd)

      say("Connecting to #{host}...", :magenta)
      Xamal.SSH.interactive_exec(host, cmd_str, ssh_config: config.ssh)
    else
      Enum.each(hosts, fn host ->
        active_port = read_active_port(host, config)
        cmd = Xamal.Commands.App.exec(config, command, port: active_port)

        case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
          {:ok, output} -> puts_by_host(host, output)
          {:error, reason} -> puts_by_host(host, "Error: #{inspect(reason)}")
        end
      end)
    end
  end

  def logs(args, _opts) do
    config = Xamal.Commander.config()
    log_opts = parse_log_opts(args)

    # For follow mode, resolve the active port for the first host
    log_opts =
      if Keyword.get(log_opts, :follow, false) do
        host = hd(Xamal.Commander.hosts())
        active_port = read_active_port(host, config)
        if active_port, do: Keyword.put(log_opts, :port, active_port), else: log_opts
      else
        log_opts
      end

    dispatch_logs(log_opts, &Xamal.Commands.App.logs(config, &1), config)
  end

  def details(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      active_port = read_active_port(host, config)
      cmd = Xamal.Commands.App.details(config, active_port)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output)
        {:error, _} -> puts_by_host(host, "(not available)")
      end
    end)
  end

  def version(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      cmd = Xamal.Commands.App.current_version(config)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output, type: "Version")
        {:error, _} -> puts_by_host(host, "(unknown)")
      end
    end)
  end

  def remove(_args, opts) do
    confirming("This will remove all releases. Are you sure?", opts, fn ->
      stop([], opts)

      config = Xamal.Commander.config()
      hosts = Xamal.Commander.hosts()

      Enum.each(hosts, fn host ->
        cmd = Xamal.Commands.Server.remove_service_directory(config)

        case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
          {:ok, _} -> say("  Removed releases on #{host}", :green)
          {:error, reason} -> say("  Error on #{host}: #{inspect(reason)}", :red)
        end
      end)
    end)
  end

  def releases(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      cmd = Xamal.Commands.App.list_releases(config)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output, type: "Releases")
        {:error, _} -> puts_by_host(host, "(none)")
      end
    end)
  end

  def stale_releases(_args, _opts) do
    config = Xamal.Commander.config()
    keep = Xamal.Configuration.retain_releases(config)
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      cmd = Xamal.Commands.App.stale_releases(config, keep)

      case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output, type: "Stale Releases")
        {:error, _} -> puts_by_host(host, "(none)")
      end
    end)
  end

  def maintenance(_args, opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    say("Enabling maintenance mode...", :magenta)

    run_hook("pre-caddy-reload", skip_hooks: skip_hooks)

    Enum.each(hosts, fn host ->
      cmd = Xamal.Commands.Caddy.write_maintenance_caddyfile(config)
      Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh)
      Xamal.SSH.execute_command(host, Xamal.Commands.Caddy.reload(config), ssh_config: config.ssh)
      say("  Maintenance mode enabled on #{host}", :green)
    end)

    run_hook("post-caddy-reload", skip_hooks: skip_hooks)
  end

  def live(_args, opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    say("Disabling maintenance mode...", :magenta)

    run_hook("pre-caddy-reload", skip_hooks: skip_hooks)

    Enum.each(hosts, fn host ->
      active_port = read_active_port(host, config) || config.caddy.app_port

      cmd = Xamal.Commands.Caddy.write_caddyfile(config, active_port)
      Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh)
      Xamal.SSH.execute_command(host, Xamal.Commands.Caddy.reload(config), ssh_config: config.ssh)
      say("  Live mode restored on #{host} (port #{active_port})", :green)
    end)

    run_hook("post-caddy-reload", skip_hooks: skip_hooks)
  end

  def help do
    IO.puts("""
    Usage: xamal app <command>

    Commands:
      boot              Start app (or restart with zero-downtime)
      start             Start existing release
      stop              Stop release
      exec [-i] CMD     Run command in release context
      logs [-f] [-n N]  Show logs (journalctl)
      details           Show running release info
      version           Show running version
      remove            Stop and remove release directories
      releases          List release directories
      stale_releases    List old (prunable) releases
      maintenance       Enable maintenance mode (503 responses)
      live              Disable maintenance mode (restore traffic)
    """)
  end

  # Private

  defp do_boot_host(config, role, host, _app_port, _alt_port, skip_hooks) do
    version = config.version

    # Upload env file
    upload_env_file(host, config, role)

    # Save old version for rollback on health check failure
    old_version =
      case ssh_exec(host, Xamal.Commands.App.current_version(config), config) do
        {:ok, v} -> String.trim(v)
        {:error, _} -> nil
      end

    # Blue-green swap: symlink, start, health check, caddy, drain, enable/disable
    new_port =
      blue_green_swap(host, config, version,
        skip_hooks: skip_hooks,
        rollback_version: old_version
      )

    say("  Booted #{role.name} on #{host} (port #{new_port})", :green)
  end

  defp upload_env_file(host, config, role) do
    env = Xamal.Configuration.Role.resolved_env(role, config.env)
    env_content = Xamal.EnvFile.encode(Xamal.Configuration.Env.to_map(env))
    env_path = Xamal.Configuration.Role.secrets_path(role, config)

    ssh_exec(host, Xamal.Commands.Base.make_directory(Path.dirname(env_path)), config)
    ssh_exec(host, Xamal.Commands.Base.write([["echo", "'#{env_content}'"], [env_path]]), config)
    ssh_exec(host, Xamal.Commands.Systemd.write_env_symlink(config, role), config)
  end

  defp execute_on(host, cmd, config) do
    case Xamal.SSH.execute_command(host, cmd, ssh_config: config.ssh) do
      {:ok, output} -> if output != "", do: IO.puts(output)
      {:error, reason} -> say("Error on #{host}: #{inspect(reason)}", :red)
    end
  end
end
