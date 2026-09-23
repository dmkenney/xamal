# Xamal

[![Hex.pm](https://img.shields.io/hexpm/v/xamal.svg)](https://hex.pm/packages/xamal)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/xamal)
[![License](https://img.shields.io/hexpm/l/xamal.svg)](https://github.com/dmkenney/xamal/blob/master/LICENSE)

Xamal is an Elixir port of [Kamal](https://github.com/basecamp/kamal) — Basecamp's tool for deploying web apps anywhere. It uses Mix tasks, Elixir configuration (`config/xamal.exs`), native releases, and Caddy instead of Docker containers and kamal-proxy.

If you're familiar with Kamal, you should feel right at home. The operational model, hook system, secrets management, and destination-based multi-environment workflow carry over.

## What's different from Kamal

- **Elixir releases** instead of Docker containers — built with `mix release`, distributed as tarballs
- **Caddy** instead of kamal-proxy — automatic TLS via Let's Encrypt, zero-downtime blue-green deploys via port switching
- **Erlang SSH** instead of shelling out to `ssh` — connection pooling via GenServer
- **Mix tasks** — deploy from the same toolchain that builds your release

Docker-specific configuration (image, registry, Dockerfile, build args, etc.) is intentionally omitted since releases replace containers entirely.

## Requirements

**Locally**, where you run the Mix tasks:

- Elixir 1.15+ / OTP 26+ and an environment that can build a release (`mix release`)
- SSH access to your target servers

**On each target server:**

- A systemd-based Linux host with SSH enabled
- Caddy — `mix xamal.server.bootstrap` (run as part of `mix xamal.setup`) installs Caddy and the systemd service unit for you if they are not already present

## Install

Add Xamal as a Mix dependency in the application you deploy:

```elixir
# mix.exs
defp deps do
  [
    {:xamal, "~> 0.5", only: [:dev, :test], runtime: false}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

Documentation is available on [HexDocs](https://hexdocs.pm/xamal).

## Upgrading

Upgrading from 0.2.0? The escript binary, the `xamal <cmd>` interface, and
`config/deploy.yml` were all replaced in 0.3.0. See [UPGRADING.md](UPGRADING.md)
for step-by-step migration instructions.

## Quick start

```sh
# Generate config stubs, sample hooks, release config, and helper aliases
mix xamal.init

# Edit config/xamal.exs and .xamal/secrets, then:
mix xamal.setup
```

Xamal ships built-in reference docs for every config section. Run `mix xamal.docs`
to list the available topics, or `mix xamal.docs <topic>` (e.g. `mix xamal.docs servers`)
for details.

## Configuration

Xamal reads Elixir config from `config/xamal.exs`:

```elixir
import Config

config :xamal,
  service: "my-app",
  servers: [
    web: ["192.168.0.1", "192.168.0.2"],
    worker: [
      hosts: ["192.168.0.3"],
      cmd: ~s(bin/my_app eval "Worker.start()")
    ]
  ],
  ssh: [
    user: "deploy"
  ],
  caddy: [
    host: "app.example.com",
    app_port: 4000
  ],
  env: [
    clear: [
      PHX_HOST: "app.example.com"
    ],
    secret: ["SECRET_KEY_BASE"]
  ],
  release: [
    name: "my_app",
    mix_env: "prod"
  ],
  health_check: [
    path: "/health"
  ]
```

**Important:** The `release.name` must match a named release in your `mix.exs`. Xamal runs `mix release <name>`, which requires an explicit release definition:

```elixir
# mix.exs
def project do
  [
    ...
    releases: [
      my_app: [
        version: {:from_app, :my_app}
      ]
    ]
  ]
end
```

Without this, `mix release my_app` will fail with `Unknown release :my_app`.

Because this is Elixir config, normal Elixir expressions such as `System.get_env/1` are available. Use regular Mix aliases in your application's `mix.exs` for command shortcuts.

Run `mix xamal.docs <topic>` for detailed reference on any config section.

## Builders

Releases are built locally by default. Two other modes exist for when the
build environment has to match the servers — ERTS, NIFs, and port drivers are
compiled into the release tarball, so they are linked against the build
machine's OpenSSL and glibc and built for its CPU architecture.

```elixir
config :xamal,
  builder: [docker: true]                  # build in a Linux container
  # builder: [docker: "hexpm/elixir:1.18.3-erlang-27.2.3-debian-bookworm-20250113"]
  # builder: [remote: "build@build-server"] # build on another host over SSH
```

**Docker** runs the build in a Linux container. Pin the image to match your
server's distro and OpenSSL. No `--platform` flag is passed, so the container
inherits your host's architecture — an arm64 laptop produces arm64 binaries.
The container bind-mounts your working directory and writes into the local
`_build`, so a stale native `_build` can leak in.

**Remote** builds on another host over SSH. Source is synced with
`git archive HEAD`, so only committed code is built — uncommitted changes are
not sent. The build host needs Elixir and OTP installed at versions matching
the targets, on the `PATH` for non-interactive SSH sessions (`~/.bashrc` is
not sourced for those). The finished tarball is copied back locally, then
uploaded to the servers like any other build.

Use remote mode when the build environment must match production exactly, or
when Docker cannot produce binaries for the target OS at all — FreeBSD, for
instance. Pointing `remote` at a deploy host is the strongest guarantee that
NIFs and OpenSSL match.

## Commands

Run `mix help | grep xamal` to list every available task.

### Deploy

```
mix xamal.setup               # Bootstrap servers and deploy
mix xamal.deploy              # Build, distribute, and boot
mix xamal.redeploy            # Deploy without bootstrapping
mix xamal.rollback VERSION    # Roll back to a previous version
mix xamal.prune               # Remove old releases, keeping the retained count
mix xamal.remove              # Remove remote release and proxy resources
```

### App

```
mix xamal.app.boot            # Zero-downtime restart
mix xamal.app.start           # Start the service on its active port (no swap)
mix xamal.app.stop            # Stop application services
mix xamal.app.exec CMD        # Run a command in the release context
mix xamal.app.logs -f         # Tail application logs
mix xamal.app.version         # Show the current deployed version per host
mix xamal.app.stale_releases  # Preview releases that pruning would remove
mix xamal.app.maintenance     # Enable maintenance mode (503)
mix xamal.app.live            # Disable maintenance mode
mix xamal.iex                 # Open a remote IEx session
mix xamal.migrate             # Run the release migrator (<App>.Release.migrate)
```

### Inspect

```
mix xamal.versions            # List release versions on servers
mix xamal.details             # Show app and proxy status
mix xamal.audit               # Show the audit log
mix xamal.version             # Print the installed Xamal version
```

### Build, server, and lock

```
mix xamal.build               # Build release tarball
mix xamal.build.upload        # Upload release tarball to servers
mix xamal.build.deliver       # Build and upload release
mix xamal.build.details       # Print build configuration
mix xamal.server.bootstrap    # Bootstrap target servers
mix xamal.server.exec CMD     # Run a shell command on servers
mix xamal.server.logs         # Show Caddy/proxy logs from servers
mix xamal.lock.status         # Check deploy lock
mix xamal.lock.acquire        # Acquire deploy lock
mix xamal.lock.release        # Release deploy lock
```

### Config, docs, and secrets

```
mix xamal.config              # Show merged configuration
mix xamal.docs hooks          # Show hook documentation
mix xamal.secrets.print       # Show secrets (redacted)
mix xamal.secrets.extract KEY # Print one secret value
mix xamal.secrets.fetch ADAPTER [OPTIONS]
```

## Hooks

Shell scripts in `.xamal/hooks/` that run locally at lifecycle points:

| Hook | When |
|---|---|
| `pre-build` | Before building the release |
| `post-build` | After building the release |
| `pre-deploy` | Before deploying |
| `post-deploy` | After deploying |
| `pre-app-boot` | Before booting the app |
| `post-app-boot` | After booting the app |
| `pre-caddy-reload` | Before Caddy config reload |
| `post-caddy-reload` | After Caddy config reload |

Hooks receive environment variables like `XAMAL_SERVICE`, `XAMAL_VERSION`, `XAMAL_HOSTS`, `XAMAL_PERFORMER`, etc. Run `mix xamal.docs hooks` for the full list.

## Destinations

Multi-environment deploys work the same as Kamal:

```sh
mix xamal.deploy -d staging
mix xamal.deploy -d production
```

With override files like `config/xamal/staging.exs` and secrets in `.xamal/secrets.staging`.

## Multiple apps on one host

Several apps can share a server and its Caddy. Each app gets its own
directory, systemd unit, and Caddyfile, and `/etc/caddy/Caddyfile` imports
them all. Give each app a distinct:

- `service`
- `release.name`
- `caddy.host` (one app per host may leave it unset and serve every other hostname)
- `caddy.app_port` (each app uses `app_port` and `app_port + 1`)

```elixir
# app one                                 # app two
caddy: [host: "one.com", app_port: 4000]  caddy: [host: "two.com", app_port: 4010]
```

`mix xamal.server.bootstrap` refuses to install an app whose release name,
ports, or catch-all site would collide with an app already on the host.
Bootstrap only adds the import line to `/etc/caddy/Caddyfile` if it is
missing, so sites you manage there yourself are kept.

Destinations of the same service share its directory, so to run staging and
production on one host, give each destination its own `service` name.

## License

MIT
