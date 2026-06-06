# Upgrading

This guide documents breaking changes and the steps required to upgrade between
major Xamal versions.

## 0.2.0 → 0.3.0

Version 0.3.0 changes how Xamal is installed, how it is invoked, and how it is
configured. There is no compatibility shim — the old escript binary and
`config/deploy.yml` are gone — so every project needs to migrate.

The deploy model itself is unchanged: the same servers, hooks, secrets, and
destination workflow carry over. Only the install method, command surface, and
config format change.

### 1. Replace the escript install with a Mix dependency

Previously Xamal was installed as a standalone escript (via `install.sh`,
`mix escript.install`, or a copied binary on your `$PATH`).

Remove the old binary:

```sh
rm -f ~/.local/bin/xamal      # or wherever you copied it
mix escript.uninstall xamal   # if you used mix escript.install
```

Then add Xamal as a dev/test dependency in the application you deploy:

```elixir
# mix.exs
defp deps do
  [
    {:xamal, "~> 0.3", only: [:dev, :test], runtime: false}
  ]
end
```

```sh
mix deps.get
```

### 2. Use `mix xamal.<task>` instead of the `xamal` binary

The command surface moved from the escript to Mix tasks. Subcommands are now
dotted task names:

| 0.2.0 (escript)         | 0.3.0 (Mix task)              |
| ----------------------- | ----------------------------- |
| `xamal init`            | `mix xamal.init`              |
| `xamal setup`           | `mix xamal.setup`             |
| `xamal deploy`          | `mix xamal.deploy`            |
| `xamal redeploy`        | `mix xamal.redeploy`          |
| `xamal rollback VER`    | `mix xamal.rollback VER`      |
| `xamal app boot`        | `mix xamal.app.boot`          |
| `xamal app exec CMD`    | `mix xamal.app.exec CMD`      |
| `xamal app logs -f`     | `mix xamal.app.logs -f`       |
| `xamal app maintenance` | `mix xamal.app.maintenance`   |
| `xamal app live`        | `mix xamal.app.live`          |
| `xamal lock status`     | `mix xamal.lock.status`       |
| `xamal secrets print`   | `mix xamal.secrets.print`     |
| `xamal config`          | `mix xamal.config`            |
| `xamal docs hooks`      | `mix xamal.docs hooks`        |

Flags carry over unchanged, including the `-d <destination>` flag. Run
`mix help | grep xamal` to list every available task.

Update any deploy scripts, CI jobs, Makefiles, or Mix aliases that called the
`xamal` binary.

### 3. Convert `config/deploy.yml` to `config/xamal.exs`

Configuration is now Elixir config instead of YAML. Translate the structure
key-for-key: YAML maps become keyword lists, and the top-level keys move under
`config :xamal`.

Before — `config/deploy.yml`:

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

After — `config/xamal.exs`:

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

If you would rather start from a fresh stub and copy your values over, delete
`config/deploy.yml` and run `mix xamal.init`, which generates `config/xamal.exs`
(along with `.xamal/secrets`, sample hooks, and `.gitignore` entries) without
overwriting files that already exist.

### 4. Replace EEx templating with Elixir expressions

`config/deploy.yml` supported EEx interpolation. Because `config/xamal.exs` is
plain Elixir, use normal Elixir expressions instead:

| 0.2.0 (EEx in YAML)               | 0.3.0 (Elixir in `.exs`)          |
| --------------------------------- | --------------------------------- |
| `<%= System.get_env("KEY") %>`    | `System.get_env("KEY")`           |
| `<%= env["KEY"] %>`               | `System.get_env("KEY")`           |

For example:

```elixir
config :xamal,
  caddy: [
    host: System.get_env("APP_HOST") || "app.example.com",
    app_port: String.to_integer(System.get_env("APP_PORT") || "4000")
  ]
```

### 5. Rename destination override files

Destination overrides moved from `config/deploy.<destination>.yml` to Elixir
files. Both of these locations are recognized:

- `config/xamal/<destination>.exs` (preferred), or
- `config/xamal.<destination>.exs`

Each override file is a standalone `config/xamal.exs`-style file
(`import Config` + `config :xamal, ...`) that is deep-merged onto the base
config. Convert each YAML override the same way as the base file:

```sh
# Before
config/deploy.staging.yml
config/deploy.production.yml

# After
config/xamal/staging.exs
config/xamal/production.exs
```

Destination secrets (`.xamal/secrets.staging`, etc.) are unchanged.

### 6. Verify

```sh
mix xamal.config -d staging   # confirm the merged config looks right
mix xamal.deploy -d staging
```
