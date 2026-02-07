defmodule Xamal.CLI.Main do
  @moduledoc """
  Main CLI commands: setup, deploy, redeploy, rollback, versions, details, audit, config, init, remove.
  """

  import Xamal.CLI.Base

  def setup(_args, opts) do
    ensure_clean_git!(opts)

    print_runtime(fn ->
      with_lock(fn ->
        record_audit("Setup started")

        say("Bootstrapping servers...", :magenta)
        Xamal.CLI.Server.run("bootstrap", [], opts)

        do_deploy(opts)

        record_audit("Setup completed")
      end)
    end)
  end

  def deploy(_args, opts) do
    ensure_clean_git!(opts)

    config = Xamal.Commander.config()
    record_audit("Deploy started", %{version: config.version})

    runtime =
      print_runtime(fn ->
        do_deploy(opts)
      end)

    record_audit("Deploy completed", %{version: config.version})
    run_hook("post-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))
    runtime
  end

  def redeploy(_args, opts) do
    ensure_clean_git!(opts)

    config = Xamal.Commander.config()
    record_audit("Redeploy started", %{version: config.version})

    runtime =
      print_runtime(fn ->
        skip_push = Keyword.get(opts, :skip_push, false)

        if skip_push do
          say("Distributing release to servers...", :magenta)
          Xamal.CLI.Build.run("pull", [], opts)
        else
          say("Building and distributing release...", :magenta)
          Xamal.CLI.Build.run("deliver", [], opts)
        end

        with_lock(fn ->
          run_hook("pre-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))

          say("Booting app...", :magenta)
          Xamal.CLI.App.run("boot", [], opts)
        end)
      end)

    record_audit("Redeploy completed", %{version: config.version})
    run_hook("post-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))
    runtime
  end

  def rollback(args, opts) do
    case args do
      [version | _] ->
        record_audit("Rollback started", %{version: version})

        print_runtime(fn ->
          with_lock(fn ->
            config = Xamal.Commander.config()
            say("Rolling back to version #{version}...", :magenta)

            run_hook("pre-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))

            roles = Xamal.Commander.roles()

            Enum.each(roles, fn role ->
              Enum.each(role.hosts, fn host ->
                say("  Rolling back #{host} (#{role.name})...", :magenta)
                do_rollback_host(config, role, host, version)
              end)
            end)

            run_hook("post-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))
          end)
        end)

        record_audit("Rollback completed", %{version: version})

      [] ->
        config = Xamal.Commander.config()

        releases =
          case on_primary(Xamal.Commands.App.list_releases(config)) do
            {:ok, output} -> output |> String.trim() |> String.split("\n", trim: true)
            {:error, _} -> []
          end

        current =
          case on_primary(Xamal.Commands.App.current_version(config)) do
            {:ok, output} -> String.trim(output)
            {:error, _} -> nil
          end

        previous =
          case Enum.drop_while(releases, fn v -> v != current end) do
            [_ | [prev | _]] -> prev
            _ -> nil
          end

        if previous do
          say("Auto-detected previous version: #{previous}", :magenta)
          rollback([previous], opts)
        else
          IO.puts(:stderr, "No previous version found to roll back to.")
          IO.puts(:stderr, "Usage: xamal rollback [VERSION]")
          System.halt(1)
        end
    end
  end

  def details(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      say("Host: #{host}", :magenta)

      active_port = read_active_port(host, config)

      case Xamal.SSH.execute_command(host, Xamal.Commands.App.details(config, active_port),
             ssh_config: config.ssh
           ) do
        {:ok, output} -> IO.puts(output)
        {:error, reason} -> say("  Error: #{inspect(reason)}", :red)
      end

      IO.puts("")
    end)
  end

  def versions(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      say("Host: #{host}", :magenta)

      releases =
        case Xamal.SSH.execute_command(host, Xamal.Commands.App.list_releases(config),
               ssh_config: config.ssh
             ) do
          {:ok, output} -> output |> String.trim() |> String.split("\n", trim: true)
          {:error, _} -> []
        end

      current =
        case Xamal.SSH.execute_command(host, Xamal.Commands.App.current_version(config),
               ssh_config: config.ssh
             ) do
          {:ok, output} -> String.trim(output)
          {:error, _} -> nil
        end

      if releases == [] do
        IO.puts("  (no releases)")
      else
        Enum.each(releases, fn version ->
          marker = if version == current, do: " (current)", else: ""
          IO.puts("  #{version}#{marker}")
        end)
      end

      IO.puts("")
    end)
  end

  def audit(_args, _opts) do
    config = Xamal.Commander.config()
    hosts = Xamal.Commander.hosts()

    Enum.each(hosts, fn host ->
      case Xamal.SSH.execute_command(host, Xamal.Commands.Auditor.reveal(config),
             ssh_config: config.ssh
           ) do
        {:ok, output} -> puts_by_host(host, output)
        {:error, _} -> puts_by_host(host, "(no audit log)")
      end
    end)
  end

  def config(_args, _opts) do
    config = Xamal.Commander.config()

    IO.puts("Service: #{Xamal.Configuration.service(config)}")
    IO.puts("Version: #{config.version}")
    IO.puts("Destination: #{config.destination || "(none)"}")
    IO.puts("")
    IO.puts("Roles:")

    Enum.each(config.roles, fn role ->
      IO.puts("  #{role.name}: #{Enum.join(role.hosts, ", ")}")
    end)

    IO.puts("")
    IO.puts("SSH: #{config.ssh.user}@*:#{config.ssh.port}")
    IO.puts("Release: #{config.release.name} (#{config.release.mix_env})")

    if config.caddy.host do
      IO.puts("Caddy: #{config.caddy.host} -> port #{config.caddy.app_port}")
    end
  end

  def init(_args, _opts) do
    # Create config/deploy.yml
    deploy_file = "config/deploy.yml"

    if File.exists?(deploy_file) do
      say("Config file already exists in #{deploy_file} (remove first to create a new one)")
    else
      File.mkdir_p!("config")
      File.write!(deploy_file, deploy_template())
      say("Created configuration file in #{deploy_file}", :green)
    end

    # Create .xamal/secrets
    secrets_file = ".xamal/secrets"

    unless File.exists?(secrets_file) do
      File.mkdir_p!(".xamal")
      File.write!(secrets_file, secrets_template())
      say("Created #{secrets_file} file", :green)
    end

    # Create .xamal/hooks directory
    hooks_dir = ".xamal/hooks"

    unless File.dir?(hooks_dir) do
      File.mkdir_p!(hooks_dir)

      Enum.each(sample_hooks(), fn {name, content} ->
        path = Path.join(hooks_dir, name)
        File.write!(path, content)
        File.chmod!(path, 0o755)
      end)

      say("Created sample hooks in #{hooks_dir}", :green)
    end
  end

  def remove(_args, opts) do
    confirming("This will remove all releases and Caddy config. Are you sure?", opts, fn ->
      config = Xamal.Commander.config()

      with_lock(fn ->
        record_audit("Remove started")

        say("Stopping app...", :magenta)
        Xamal.CLI.App.run("stop", [], opts)

        say("Removing systemd units...", :magenta)
        on_hosts(Xamal.Commands.Systemd.disable_all(config))
        on_hosts(Xamal.Commands.Systemd.remove_unit(config))

        say("Removing service directory...", :magenta)
        on_hosts(Xamal.Commands.Server.remove_service_directory(config))

        record_audit("Remove completed")
        say("Removed!", :green)
      end)
    end)
  end

  # Private

  defp do_deploy(opts) do
    skip_push = Keyword.get(opts, :skip_push, false)

    if skip_push do
      say("Distributing release to servers...", :magenta)
      Xamal.CLI.Build.run("pull", [], opts)
    else
      say("Building and distributing release...", :magenta)
      Xamal.CLI.Build.run("deliver", [], opts)
    end

    with_lock(fn ->
      run_hook("pre-deploy", skip_hooks: Keyword.get(opts, :skip_hooks, false))

      say("Booting app on servers...", :magenta)
      Xamal.CLI.App.run("boot", [], opts)

      say("Pruning old releases...", :magenta)
      Xamal.CLI.Prune.prune([], opts)
    end)
  end

  defp do_rollback_host(config, _role, host, version) do
    new_port = blue_green_swap(host, config, version)
    say("  Rolled back #{host} to #{version} (port #{new_port})", :green)
  end

  defp deploy_template do
    """
    service: my-app

    servers:
      web:
        - 192.168.0.1

    ssh:
      user: deploy

    caddy:
      host: app.example.com
      app_port: 4000

    env:
      clear:
        PHX_HOST: app.example.com
      secret:
        - SECRET_KEY_BASE

    release:
      name: my_app
      mix_env: prod

    health_check:
      path: /health
    """
  end

  defp secrets_template do
    """
    # Secrets are loaded from this file and made available as env vars on the server.
    # Use command substitution to fetch secrets from a vault:
    #   SECRET_KEY_BASE=$(op read "op://Vault/Item/Field")

    SECRET_KEY_BASE=change_me
    """
  end

  defp sample_hooks do
    [
      {"pre-build",
       """
       #!/bin/sh
       echo "Running pre-build hook..."
       """},
      {"pre-deploy",
       """
       #!/bin/sh
       echo "Running pre-deploy hook..."
       """},
      {"post-deploy",
       """
       #!/bin/sh
       echo "Running post-deploy hook..."
       """},
      {"pre-app-boot",
       """
       #!/bin/sh
       echo "Running pre-app-boot hook..."
       """},
      {"post-app-boot",
       """
       #!/bin/sh
       echo "Running post-app-boot hook..."
       """},
      {"pre-caddy-reload",
       """
       #!/bin/sh
       echo "Running pre-caddy-reload hook..."
       """},
      {"post-caddy-reload",
       """
       #!/bin/sh
       echo "Running post-caddy-reload hook..."
       """}
    ]
  end
end
