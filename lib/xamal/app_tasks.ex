defmodule Xamal.AppTasks do
  @moduledoc """
  Application task implementations.
  """

  import Xamal.Hooks
  import Xamal.Logs
  import Xamal.Output
  import Xamal.Remote
  alias Xamal.Commands.App, as: AppCommand
  alias Xamal.Commands.Base, as: CommandBase
  alias Xamal.Commands.Caddy
  alias Xamal.Commands.Systemd
  alias Xamal.Configuration
  alias Xamal.Context
  alias Xamal.EnvFile
  alias Xamal.SSH
  alias Xamal.Utils

  def boot(_args, opts, context) do
    config = context.config
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    run_hook("pre-app-boot", [skip_hooks: skip_hooks], context)
    Enum.each(Context.roles(context), &boot_role(&1, config, skip_hooks, context))
    run_hook("post-app-boot", [skip_hooks: skip_hooks], context)
  end

  def stop(_args, _opts, context) do
    config = context.config
    hosts = Context.hosts(context)

    Enum.each(hosts, fn host ->
      say("  Stopping on #{host}...", :magenta)
      cmd = Systemd.stop_all(config)

      case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, _} -> say("  Stopped on #{host}", :green)
        {:error, _} -> say("  App not running on #{host}", :yellow)
      end
    end)
  end

  def exec(args, _opts, context) do
    config = context.config
    hosts = Context.hosts(context)
    {exec_opts, command} = parse_exec(args)

    if Keyword.get(exec_opts, :interactive, false) do
      interactive_exec(hd(hosts), config, command)
    else
      Enum.each(hosts, &remote_exec(&1, config, command))
    end
  end

  def logs(args, _opts, context) do
    config = context.config
    log_opts = parse_log_opts(args)

    # For follow mode, resolve the active port for the first host
    log_opts =
      if Keyword.get(log_opts, :follow, false) do
        host = hd(Context.hosts(context))
        active_port = read_active_port(host, config)
        if active_port, do: Keyword.put(log_opts, :port, active_port), else: log_opts
      else
        log_opts
      end

    dispatch_logs(log_opts, &AppCommand.logs(config, &1), config, [], context)
  end

  def maintenance(_args, opts, context) do
    config = context.config
    hosts = Context.hosts(context)
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    say("Enabling maintenance mode...", :magenta)

    run_hook("pre-caddy-reload", [skip_hooks: skip_hooks], context)

    Enum.each(hosts, fn host ->
      cmd = Caddy.write_maintenance_caddyfile(config)
      SSH.execute_command(host, cmd, ssh_config: config.ssh)
      SSH.execute_command(host, Caddy.reload(config), ssh_config: config.ssh)
      say("  Maintenance mode enabled on #{host}", :green)
    end)

    run_hook("post-caddy-reload", [skip_hooks: skip_hooks], context)
  end

  @doc """
  Starts the systemd service on the currently active port without a full boot.

  Use this to bring an app back up after `mix xamal.app.stop`; `mix xamal.app.boot`
  performs the heavier zero-downtime swap instead.
  """
  def start(_args, _opts, context) do
    config = context.config

    Enum.each(Context.hosts(context), fn host ->
      active_port = read_active_port(host, config) || config.caddy.app_port
      say("  Starting on #{host} (port #{active_port})...", :magenta)
      cmd = Systemd.start(config, active_port)

      case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, _} -> say("  Started on #{host} (port #{active_port})", :green)
        {:error, reason} -> say("  Error on #{host}: #{inspect(reason)}", :red)
      end
    end)
  end

  @doc """
  Prints the current release version on the selected hosts.

  See also `mix xamal.versions`, which lists every release and marks the current one.
  """
  def version(_args, _opts, context) do
    config = context.config

    Enum.each(Context.hosts(context), fn host ->
      case SSH.execute_command(host, AppCommand.current_version(config), ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, String.trim(output), type: "Version")
        {:error, _} -> puts_by_host(host, "(unknown)", type: "Version")
      end
    end)
  end

  @doc """
  Lists releases that would be removed by pruning (a read-only preview).

  `mix xamal.prune` performs the actual removal.
  """
  def stale_releases(_args, _opts, context) do
    config = context.config
    keep = Configuration.retain_releases(config)

    Enum.each(Context.hosts(context), fn host ->
      cmd = AppCommand.stale_releases(config, keep)

      case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output, type: "Stale Releases")
        {:error, _} -> puts_by_host(host, "(none)", type: "Stale Releases")
      end
    end)
  end

  @doc """
  Opens an interactive remote shell (IEx) connected to the running release.

  Convenience wrapper for `mix xamal.app.exec -i`.
  """
  def shell(_args, opts, context) do
    exec(["-i"], opts, context)
  end

  @doc """
  Opens an interactive remote IEx session connected to the running release.

  Alias of `shell/3`; both connect via the release's `remote` command.
  """
  def iex(_args, opts, context) do
    exec(["-i"], opts, context)
  end

  @doc """
  Runs the release migrator on the selected hosts.

  Calls `<AppModule>.Release.migrate()` via the release's RPC, following the
  conventional `mix phx.gen.release`-style `Release` module. Override the module
  by passing it as an argument, e.g. `mix xamal.migrate MyApp.Release`.
  """
  def migrate(args, opts, context) do
    module = migrate_module(args, context.config)
    exec(["#{module}.migrate()"], opts, context)
  end

  defp migrate_module([module | _], _config) when is_binary(module) and module != "" do
    String.trim_trailing(module, ".migrate()")
  end

  defp migrate_module(_args, config) do
    "#{Utils.to_module_name(config.release.name)}.Release"
  end

  def live(_args, opts, context) do
    config = context.config
    hosts = Context.hosts(context)
    skip_hooks = Keyword.get(opts, :skip_hooks, false)

    say("Disabling maintenance mode...", :magenta)

    run_hook("pre-caddy-reload", [skip_hooks: skip_hooks], context)

    Enum.each(hosts, fn host ->
      active_port = read_active_port(host, config) || config.caddy.app_port

      cmd = Caddy.write_caddyfile(config, active_port)
      SSH.execute_command(host, cmd, ssh_config: config.ssh)
      SSH.execute_command(host, Caddy.reload(config), ssh_config: config.ssh)
      say("  Live mode restored on #{host} (port #{active_port})", :green)
    end)

    run_hook("post-caddy-reload", [skip_hooks: skip_hooks], context)
  end

  defp boot_role(role, config, skip_hooks, context) do
    role
    |> host_batches(config.boot)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      boot_batch(batch, index, role, config, skip_hooks, context)
    end)
  end

  defp host_batches(role, boot_config) do
    case Configuration.Boot.resolved_limit(boot_config, length(role.hosts)) do
      nil -> [role.hosts]
      limit -> Enum.chunk_every(role.hosts, limit)
    end
  end

  defp boot_batch(batch, index, role, config, skip_hooks, context) do
    maybe_wait_before_batch(index, config.boot.wait)

    Enum.each(batch, fn host ->
      say("  Booting #{role.name} on #{host}...", :magenta)
      do_boot_host(config, role, host, skip_hooks, context)
    end)
  end

  defp maybe_wait_before_batch(index, wait) when index > 0 and not is_nil(wait) do
    say("  Waiting #{wait}s before next batch...", :magenta)
    Process.sleep(wait * 1000)
  end

  defp maybe_wait_before_batch(_index, _wait), do: :ok

  defp parse_exec(args) do
    {exec_opts, cmd_args, _invalid} =
      OptionParser.parse(args, switches: [interactive: :boolean], aliases: [i: :interactive])

    {exec_opts, Enum.join(cmd_args, " ")}
  end

  defp interactive_exec(host, config, command) do
    active_port = read_active_port(host, config)
    cmd = AppCommand.exec(config, command, interactive: true, port: active_port)

    say("Connecting to #{host}...", :magenta)
    SSH.interactive_exec(host, CommandBase.to_command_string(cmd), ssh_config: config.ssh)
  end

  defp remote_exec(host, config, command) do
    active_port = read_active_port(host, config)
    cmd = AppCommand.exec(config, command, port: active_port)

    case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
      {:ok, output} -> puts_by_host(host, output)
      {:error, reason} -> puts_by_host(host, "Error: #{inspect(reason)}")
    end
  end

  defp do_boot_host(config, role, host, skip_hooks, context) do
    upload_env_file(host, config, role)

    new_port =
      Xamal.BlueGreen.swap(
        host,
        config,
        config.version,
        [
          skip_hooks: skip_hooks,
          rollback_version: current_version(host, config)
        ],
        context
      )

    say("  Booted #{role.name} on #{host} (port #{new_port})", :green)
  end

  defp current_version(host, config) do
    case ssh_exec(host, AppCommand.current_version(config), config) do
      {:ok, version} -> String.trim(version)
      {:error, _} -> nil
    end
  end

  defp upload_env_file(host, config, role) do
    env = Configuration.Role.resolved_env(role, config.env)
    env_content = EnvFile.encode(Configuration.Env.to_map(env))
    env_path = Configuration.Role.secrets_path(role, config)

    ssh_exec(host, CommandBase.make_directory(Path.dirname(env_path)), config)
    ssh_exec(host, CommandBase.write([["echo", "'#{env_content}'"], [env_path]]), config)
    ssh_exec(host, Systemd.write_env_symlink(config, role), config)
  end
end
