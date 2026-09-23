defmodule Xamal.ServerTasks do
  @moduledoc """
  Server task implementations.
  """

  import Xamal.Logs
  import Xamal.Output
  import Xamal.Remote, only: [read_active_port: 2, reload_caddy!: 2]

  alias Xamal.Commands.{Caddy, Server, Systemd}
  alias Xamal.{Configuration, Context, SSH}

  def exec(args, _opts, context) do
    command = Enum.join(args, " ")

    if command == "" do
      say("Usage: mix xamal.server.exec COMMAND", :red)
    else
      exec_on_hosts(command, context.config, Context.hosts(context))
    end
  end

  defp exec_on_hosts(command, config, hosts) do
    Enum.each(hosts, fn host ->
      case SSH.execute(host, command, ssh_config: config.ssh) do
        {:ok, output} -> puts_by_host(host, output, type: "Server")
        {:error, reason} -> puts_by_host(host, "Error: #{inspect(reason)}", type: "Server")
      end
    end)
  end

  def bootstrap(_args, _opts, context) do
    config = context.config
    hosts = Context.hosts(context)

    say("Bootstrapping #{length(hosts)} server(s)...", :magenta)

    Enum.each(hosts, fn host ->
      say("  Bootstrapping #{host}...", :magenta)

      # Check if Caddy is installed
      case SSH.execute_command(host, Caddy.check_installed(), ssh_config: config.ssh) do
        {:ok, _} ->
          say("  Caddy already installed on #{host}", :green)

        {:error, _} ->
          say("  Installing Caddy on #{host}...", :magenta)
          install_cmd = Caddy.install()
          SSH.execute_command(host, install_cmd, ssh_config: config.ssh, timeout: 120_000)
      end

      # Other apps may already live on this host; refuse before touching
      # anything that would clobber them.
      check_host_conflicts!(host, config)

      # Create directory structure
      bootstrap_cmd = Server.bootstrap(config)
      SSH.execute_command(host, bootstrap_cmd, ssh_config: config.ssh)

      # Install systemd service unit
      say("  Installing systemd service unit on #{host}...", :magenta)

      SSH.execute_command(host, Systemd.install_unit(config), ssh_config: config.ssh)

      # Generate the Caddyfile against whichever port is serving right now.
      #
      # bootstrap is not only a first-run command: it is the only way to
      # re-render the systemd unit after a config change (drain_timeout, user,
      # service directory), so it gets run against live servers. Blue-green
      # leaves the app on app_port or alt_port depending on how many deploys
      # have landed, and writing app_port unconditionally pointed Caddy at the
      # idle port and reloaded — an outage on every already-deployed server
      # sitting on alt_port.
      upstream_port = caddy_upstream_port(read_active_port(host, config), config)
      caddyfile_cmd = Caddy.write_caddyfile(config, upstream_port)
      SSH.execute_command(host, caddyfile_cmd, ssh_config: config.ssh)

      # Make sure the system Caddyfile imports every service Caddyfile
      # (appends the import line only if missing; nothing else is touched).
      SSH.execute_command(host, Caddy.configure_system_caddyfile(), ssh_config: config.ssh)

      SSH.execute_command(host, Caddy.enable(), ssh_config: config.ssh)
      reload_caddy!(host, config)

      say("  Bootstrapped #{host}", :green)
    end)
  end

  # Each check succeeds (exit 0) only when it finds a conflict.
  defp check_host_conflicts!(host, config) do
    case SSH.execute_command(host, Systemd.units_under_other_names(config),
           ssh_config: config.ssh
         ) do
      {:ok, found} -> raise Xamal.BlueGreen.renamed_release_message(host, config, found)
      {:error, _} -> :ok
    end

    release = config.release.name
    ports = "#{config.caddy.app_port}/#{Configuration.Caddy.alt_port(config.caddy)}"

    port_message =
      "another app on #{host} already uses ports #{ports}. Set caddy.app_port " <>
        "so this app's two ports (app_port and app_port + 1) are free."

    checks =
      [
        {Systemd.unit_owned_by_other_service(config),
         "another app on #{host} already uses the release name #{inspect(release)} " <>
           "(systemd unit #{release}@.service). Set a different release.name."},
        # Ports recorded by other apps' bootstrap, then running units (covers
        # apps bootstrapped before the ports file existed).
        {Server.claimed_port_conflicts(config), port_message},
        {Systemd.port_conflicts(config), port_message}
      ] ++ catch_all_check(host, config)

    Enum.each(checks, fn {cmd, message} ->
      case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
        {:ok, found} -> raise "Cannot bootstrap: #{message}\n#{found}"
        {:error, _} -> :ok
      end
    end)
  end

  # Only an app with no caddy.host gets the :80 catch-all site.
  defp catch_all_check(host, config) do
    if Configuration.Caddy.hostnames(config.caddy) == [] do
      [
        {Caddy.catch_all_conflicts(config),
         "another app on #{host} already serves every hostname on :80 (it has no " <>
           "caddy.host). Set caddy.host for this app."}
      ]
    else
      []
    end
  end

  @doc false
  # Which port bootstrap's Caddyfile should proxy to.
  #
  # A fresh server has no active_port file, so read_active_port/2 returns nil
  # and app_port is correct. Otherwise trust the recorded port, but only if it
  # is one of the two the blue-green swap actually uses — a truncated or
  # hand-edited active_port file must not become a Caddy upstream.
  def caddy_upstream_port(active_port, config) do
    app_port = config.caddy.app_port
    alt_port = Configuration.Caddy.alt_port(config.caddy)

    if active_port in [app_port, alt_port], do: active_port, else: app_port
  end

  def logs(args, _opts, context) do
    config = context.config
    log_opts = parse_log_opts(args)

    dispatch_logs(log_opts, &Caddy.logs/1, config, [type: "Server"], context)
  end
end
