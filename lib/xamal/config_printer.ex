defmodule Xamal.ConfigPrinter do
  @moduledoc false

  alias Xamal.Configuration

  def print(_args, _opts, context), do: print(context.config)

  def print(config) do
    IO.puts("Service: #{Configuration.service(config)}")
    IO.puts("Version: #{config.version}")
    IO.puts("Destination: #{config.destination || "(none)"}")
    IO.puts("")
    IO.puts("Roles:")

    Enum.each(config.roles, fn role ->
      IO.puts(
        "  #{role.name}: #{Enum.map_join(role.hosts, ", ", &Configuration.host_label(config, &1))}"
      )
    end)

    IO.puts("")
    IO.puts("SSH: #{config.ssh.user}@*:#{config.ssh.port}")
    IO.puts("Release: #{config.release.name} (#{config.release.mix_env})")

    if config.caddy.host do
      IO.puts("Caddy: #{config.caddy.host} -> port #{config.caddy.app_port}")
    end
  end
end
