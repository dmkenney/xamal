# Xamal

Xamal is an Elixir port of [Kamal](https://github.com/basecamp/kamal) — Basecamp's tool for deploying web apps anywhere. It retains the same config file structure (`config/deploy.yml`), command interface, and operational model, but replaces Docker containers with native Elixir releases and kamal-proxy with Caddy.

If you're familiar with Kamal, you should feel right at home. The CLI commands, YAML configuration keys, hook system, secrets management, and destination-based multi-environment workflow all carry over.

## What's different from Kamal

- **Elixir releases** instead of Docker containers — built with `mix release`, distributed as tarballs
- **Caddy** instead of kamal-proxy — automatic TLS via Let's Encrypt, zero-downtime blue-green deploys via port switching
- **Erlang SSH** instead of shelling out to `ssh` — connection pooling via GenServer
- **Escript CLI** — single binary built with `mix escript.build`

Docker-specific configuration (image, registry, Dockerfile, build args, etc.) is intentionally omitted since releases replace containers entirely.

## Install

Requires Elixir 1.15+ and Erlang/OTP 26+.

```sh
git clone https://github.com/dmkenney/xamal.git
cd xamal
mix deps.get
mix escript.build
```

This produces a `xamal` binary in the project root. Install it to your PATH:

```sh
mix escript.install
```

This places the binary in `~/.mix/escripts/`. Make sure that directory is on your `$PATH`:

```sh
export PATH="$PATH:$HOME/.mix/escripts"
```

Add that line to your `~/.bashrc` or `~/.zshrc` to make it permanent.

If you use [asdf](https://asdf-vm.com/) to manage Elixir versions, run `asdf reshim elixir` after installing.

## Quick start

```sh
# Generate config stubs and sample hooks
xamal init

# Edit config/deploy.yml and .kamal/secrets, then:
xamal setup
```

## Configuration

Xamal reads `config/deploy.yml` with the same structure as Kamal:

```yaml
service: my-app

servers:
  web:
    - 192.168.0.1
    - 192.168.0.2
  worker:
    hosts:
      - 192.168.0.3
    cmd: bin/my_app eval "Worker.start()"

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
```

EEx templating is supported (`<%= env["KEY"] %>`, `<%= System.get_env("KEY") %>`).

Run `xamal docs <topic>` for detailed reference on any config section.

## Commands

```
xamal setup               # Bootstrap servers and deploy
xamal deploy              # Build, distribute, and boot
xamal redeploy            # Deploy without bootstrapping
xamal rollback VERSION    # Roll back to a previous version
xamal app boot            # Zero-downtime restart
xamal app exec CMD        # Run a command on servers
xamal app logs -f         # Tail logs
xamal app maintenance     # Enable maintenance mode (503)
xamal app live            # Disable maintenance mode
xamal lock status         # Check deploy lock
xamal secrets print       # Show secrets (redacted)
xamal config              # Show merged configuration
xamal docs hooks          # Show hook documentation
```

## Hooks

Shell scripts in `.kamal/hooks/` that run locally at lifecycle points:

| Hook | When |
|---|---|
| `pre-build` | Before building the release |
| `pre-deploy` | Before deploying |
| `post-deploy` | After deploying |
| `pre-app-boot` | Before booting the app |
| `post-app-boot` | After booting the app |
| `pre-caddy-reload` | Before Caddy config reload |
| `post-caddy-reload` | After Caddy config reload |

Hooks receive environment variables like `XAMAL_SERVICE`, `XAMAL_VERSION`, `XAMAL_HOSTS`, `XAMAL_PERFORMER`, etc. Run `xamal docs hooks` for the full list.

## Destinations

Multi-environment deploys work the same as Kamal:

```sh
xamal deploy -d staging
xamal deploy -d production
```

With override files like `config/deploy.staging.yml` and secrets in `.kamal/secrets.staging`.

## License

MIT
