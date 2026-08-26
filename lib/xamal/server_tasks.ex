defmodule Xamal.ServerTasks do
  @moduledoc """
  Server task implementations.
  """

  import Xamal.Logs
  import Xamal.Output
  import Xamal.Remote, only: [read_active_port: 2]

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

      # Point system Caddyfile to import service Caddyfiles (survives reboot)
      SSH.execute_command(host, Caddy.configure_system_caddyfile(), ssh_config: config.ssh)

      # Start/reload Caddy
      SSH.execute_command(host, Caddy.reload(config), ssh_config: config.ssh)

      say("  Bootstrapped #{host}", :green)
    end)
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
