defmodule Xamal.CLI.Server do
  @moduledoc """
  CLI commands for server management.
  """

  import Xamal.CLI.Base

  def run(subcommand, args, opts) do
    case subcommand do
      "exec" -> exec(args, opts)
      "bootstrap" -> bootstrap(args, opts)
      "logs" -> logs(args, opts)
      other -> say("Unknown server command: #{other}", :red)
    end
  end

  def exec(args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()
    command = Enum.join(args, " ")

    if command == "" do
      say("Usage: xamal server exec COMMAND", :red)
    else
      Enum.each(hosts, fn host ->
        case Xamal.SSH.execute(host, command, ssh_config: config.ssh) do
          {:ok, output} -> puts_by_host(host, output, type: "Server")
          {:error, reason} -> puts_by_host(host, "Error: #{inspect(reason)}", type: "Server")
        end
      end)
    end
  end

  def bootstrap(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    say("Bootstrapping #{length(hosts)} server(s)...", :magenta)

    Enum.each(hosts, fn host ->
      say("  Bootstrapping #{host}...", :magenta)

      # Check if Caddy is installed
      case Xamal.SSH.execute_command(host, Xamal.Commands.Caddy.check_installed(),
             ssh_config: config.ssh
           ) do
        {:ok, _} ->
          say("  Caddy already installed on #{host}", :green)

        {:error, _} ->
          say("  Installing Caddy on #{host}...", :magenta)
          install_cmd = Xamal.Commands.Caddy.install()
          Xamal.SSH.execute_command(host, install_cmd, ssh_config: config.ssh, timeout: 120_000)
      end

      # Create directory structure
      bootstrap_cmd = Xamal.Commands.Server.bootstrap(config)
      Xamal.SSH.execute_command(host, bootstrap_cmd, ssh_config: config.ssh)

      # Install systemd service unit
      say("  Installing systemd service unit on #{host}...", :magenta)

      Xamal.SSH.execute_command(host, Xamal.Commands.Systemd.install_unit(config),
        ssh_config: config.ssh
      )

      # Generate initial Caddyfile
      caddyfile_cmd = Xamal.Commands.Caddy.write_caddyfile(config, config.caddy.app_port)
      Xamal.SSH.execute_command(host, caddyfile_cmd, ssh_config: config.ssh)

      # Point system Caddyfile to import service Caddyfiles (survives reboot)
      Xamal.SSH.execute_command(host, Xamal.Commands.Caddy.configure_system_caddyfile(),
        ssh_config: config.ssh
      )

      # Start/reload Caddy
      Xamal.SSH.execute_command(host, Xamal.Commands.Caddy.reload(config), ssh_config: config.ssh)

      say("  Bootstrapped #{host}", :green)
    end)
  end

  def logs(args, _opts) do
    config = Xamal.Commander.config()
    log_opts = parse_log_opts(args)

    dispatch_logs(log_opts, &Xamal.Commands.Caddy.logs/1, config, type: "Server")
  end

  def help do
    IO.puts("""
    Usage: xamal server <command>

    Commands:
      exec CMD          Run arbitrary command via SSH on all servers
      bootstrap         Install Caddy and setup directories
      logs [-f] [-n N]  Show Caddy proxy logs (journalctl)
    """)
  end
end
