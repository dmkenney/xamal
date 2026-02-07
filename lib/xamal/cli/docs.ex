defmodule Xamal.CLI.Docs do
  @moduledoc """
  Inline configuration documentation viewer.
  """

  def run(args) do
    case args do
      [] -> print_topics()
      [topic | _] -> print_topic(topic)
    end
  end

  defp print_topics do
    IO.puts("""
    Xamal Configuration Reference

    Usage: xamal docs <topic>

    Topics:
      config          deploy.yml overview and structure
      servers         Server and role configuration
      ssh             SSH connection options
      caddy           Caddy reverse proxy and TLS
      env             Environment variables (clear and secret)
      release         Elixir release settings
      health_check    Health check configuration
      boot            Rolling deploy options (limit, wait)
      builder         Build configuration (local, docker, remote)
      hooks           Hook scripts (lifecycle events)
      secrets         Secrets management and adapters
      destinations    Multi-environment destinations
      aliases         Command aliases
    """)
  end

  defp print_topic("config") do
    IO.puts("""
    # deploy.yml Configuration

    Xamal reads configuration from `config/deploy.yml` (or a custom path via -c).
    The file supports EEx template evaluation:

      service: <%= env["SERVICE_NAME"] || "my-app" %>
      service: <%= System.get_env("SERVICE_NAME") || "my-app" %>

    ## Top-level keys

      service:            App name (required)
      servers:            Server/role definitions (required)
      ssh:                SSH connection options
      caddy:              Reverse proxy configuration
      env:                Environment variables
      release:            Elixir release settings
      health_check:       Health check configuration
      boot:               Rolling deploy options
      builder:            Build configuration
      hooks_path:         Path to hook scripts (default: .xamal/hooks)
      secrets_path:       Path to secrets file (default: .xamal/secrets)
      readiness_delay:    Seconds to wait before health checks (default: 7)
      deploy_timeout:     Max deploy time in seconds (default: 30)
      drain_timeout:      Seconds to drain old release (default: 30)
      retain_releases:    Number of old releases to keep (default: 5)
      primary_role:       Primary role name (default: web)
      aliases:            Command aliases
    """)
  end

  defp print_topic("servers") do
    IO.puts("""
    # Server Configuration

    ## Simple (hosts only)

      servers:
        web:
          - 192.168.0.1
          - 192.168.0.2

    ## Extended (with role options)

      servers:
        web:
          - 192.168.0.1
        worker:
          hosts:
            - 192.168.0.3
          cmd: bin/my_app eval "Worker.start()"
          env:
            clear:
              WORKER_MODE: "true"

    ## Tags

      servers:
        web:
          hosts:
            - 192.168.0.1
          tags:
            region: us-east

    The primary role (default: "web") is used for lock management and
    single-host operations like `xamal app exec`.
    """)
  end

  defp print_topic("ssh") do
    IO.puts("""
    # SSH Configuration

      ssh:
        user: deploy          # SSH user (default: root)
        port: 22              # SSH port (default: 22)
        proxy: jump-host      # SSH proxy/jump host
        keys: ["~/.ssh/id_ed25519"]  # Specific key files
        keys_only: true       # Only use specified keys

    SSH connections use Erlang's :ssh stdlib with connection pooling.
    Connections are reused across commands and time out after 900s idle.
    """)
  end

  defp print_topic("caddy") do
    IO.puts("""
    # Caddy Configuration

      caddy:
        host: app.example.com       # Domain for auto-TLS (Let's Encrypt)
        app_port: 4000              # Port the Elixir app listens on (default: 4000)

    ## Multiple domains

      caddy:
        host: app.example.com
        hosts:
          - www.example.com

    Caddy automatically provisions TLS certificates via Let's Encrypt.
    During deploys, Caddy switches between app_port and app_port+1
    for zero-downtime blue-green deployments.

    The generated Caddyfile lives at /opt/xamal/<service>/Caddyfile.

    ## Maintenance mode

      xamal app maintenance    # Serve 503 responses
      xamal app live           # Restore normal traffic
    """)
  end

  defp print_topic("env") do
    IO.puts("""
    # Environment Variables

      env:
        clear:
          PHX_HOST: app.example.com
          DATABASE_URL: ecto://...
        secret:
          - SECRET_KEY_BASE
          - DATABASE_PASSWORD

    Clear values are stored in the deploy.yml. Secret values are loaded
    from .xamal/secrets (dotenv format) and uploaded to each server.

    Secret files support command substitution:

      SECRET_KEY_BASE=$(op read "op://Vault/Item/Field")

    Environment files are uploaded per-role to:
      /opt/xamal/<service>/env/roles/<role>.env
    """)
  end

  defp print_topic("release") do
    IO.puts("""
    # Release Configuration

      release:
        name: my_app          # Mix release name (default: service name underscored)
        mix_env: prod         # Mix environment (default: prod)

    The release name should match your mix.exs release configuration.
    Xamal builds with `MIX_ENV=<mix_env> mix release <name>` and
    packages the result as a tarball for distribution.
    """)
  end

  defp print_topic("health_check") do
    IO.puts("""
    # Health Check Configuration

      health_check:
        path: /health         # HTTP path to poll (default: /health)
        interval: 1           # Seconds between checks (default: 1)
        timeout: 30           # Max seconds to wait (default: 30)

    During deploys, Xamal polls the new release's health check endpoint
    before switching traffic. The app must return HTTP 200 on this path.

    Tip: Use Phoenix's built-in health check or add a simple plug:

      get "/health", fn conn, _ -> send_resp(conn, 200, "ok") end
    """)
  end

  defp print_topic("boot") do
    IO.puts("""
    # Boot/Rolling Deploy Configuration

      boot:
        limit: 10             # Max hosts to boot simultaneously
        wait: 2               # Seconds between batches

    By default, all hosts boot in parallel. Set `limit` to roll out
    gradually. The `wait` option adds a pause between batches.

    Example: With 20 servers and limit=5, hosts boot in 4 batches
    of 5, with a 2-second pause between each batch.
    """)
  end

  defp print_topic("builder") do
    IO.puts("""
    # Builder Configuration

      builder:
        local: true           # Build on dev machine (default)

    ## Docker cross-compilation

      builder:
        docker: true          # Build inside Docker container

    ## Remote build

      builder:
        remote: build@build-server

    The default local builder runs `mix release` on your dev machine.
    Use Docker mode when your dev OS differs from the server OS.
    Remote mode builds on a dedicated build server via SSH.
    """)
  end

  defp print_topic("hooks") do
    IO.puts("""
    # Hook Scripts

    Hooks are shell scripts in .xamal/hooks/ (configurable via hooks_path).
    They run on the LOCAL machine, not on servers.

    ## Supported hooks

      pre-build             Before building the release
      pre-deploy            Before deploying
      post-deploy           After deploying
      pre-app-boot          Before booting the app across roles
      post-app-boot         After booting the app across roles
      pre-caddy-reload      Before writing Caddyfile and reloading Caddy
      post-caddy-reload     After Caddy reload completes

    ## Hook environment variables

      XAMAL_SERVICE           Service name
      XAMAL_VERSION           Version being deployed
      XAMAL_HOSTS             Comma-separated host list
      XAMAL_ROLE              Current role
      XAMAL_DESTINATION       Destination name
      XAMAL_COMMAND           Current command (e.g. "deploy")
      XAMAL_SUBCOMMAND        Current subcommand (e.g. "app")
      XAMAL_RECORDED_AT       ISO 8601 timestamp of hook invocation
      XAMAL_PERFORMER         Git user name + email, or system username
      XAMAL_SERVICE_VERSION   "service@version" identifier
      XAMAL_LOCK              "true" if deploy lock is held, "false" otherwise

    ## Skipping hooks

      xamal deploy --skip-hooks
      xamal deploy -H
    """)
  end

  defp print_topic("secrets") do
    IO.puts("""
    # Secrets Management

    Secrets are loaded from dotenv files:

      .xamal/secrets-common       Shared across all destinations
      .xamal/secrets              Default secrets
      .xamal/secrets.<dest>       Destination-specific secrets

    ## Format

      # Comments start with #
      SECRET_KEY_BASE=my_secret_value
      QUOTED_VALUE="value with spaces"
      FROM_VAULT=$(op read "op://Vault/Item/Field")

    ## Fetching from external sources

      xamal secrets fetch 1password <vault> <item> <field>
      xamal secrets fetch aws_secrets_manager [--from PREFIX] SECRET
      xamal secrets fetch bitwarden --account EMAIL ITEM
      xamal secrets fetch doppler <project> <config>
      xamal secrets fetch gcp_secret_manager [--account USER] SECRET
      xamal secrets fetch last_pass --account EMAIL SECRET
      xamal secrets fetch passbolt [--from FOLDER] SECRET

    ## Viewing secrets

      xamal secrets print       # Show all (values redacted)
      xamal secrets extract KEY  # Show single value (unredacted)
    """)
  end

  defp print_topic("destinations") do
    IO.puts("""
    # Destinations (Multi-Environment)

    Destinations let you deploy to different environments (staging, production)
    from the same config base.

      config/deploy.yml               Base configuration
      config/deploy.staging.yml       Staging overrides
      config/deploy.production.yml    Production overrides

    ## Usage

      xamal deploy -d staging
      xamal deploy -d production

    Destination files are deep-merged over the base config. Only include
    keys you want to override:

      # config/deploy.staging.yml
      servers:
        web:
          - staging.example.com
      caddy:
        host: staging.example.com
        app_port: 4000

    Secrets also support destinations:

      .xamal/secrets.staging
      .xamal/secrets.production
    """)
  end

  defp print_topic("aliases") do
    IO.puts("""
    # Command Aliases

    Define shortcuts in deploy.yml:

      aliases:
        console: app exec -i "bin/my_app remote"
        logs: app logs -f
        info: config

    ## Usage

      xamal console       # Runs: xamal app exec -i "bin/my_app remote"
      xamal logs           # Runs: xamal app logs -f
      xamal info           # Runs: xamal config
    """)
  end

  defp print_topic(topic) do
    IO.puts("Unknown topic: #{topic}")
    print_topics()
  end
end
