defmodule Xamal.BlueGreen do
  @moduledoc false

  import Xamal.Hooks
  import Xamal.Output
  import Xamal.Remote

  alias Xamal.Commands.{Caddy, Server, Systemd}
  alias Xamal.{Configuration, HealthCheck}

  def swap(host, config, version, opts, context) do
    refuse_renamed_release!(host, config)
    ports = select_ports(host, config)
    sync_unit(host, config)
    ssh_exec(host, Server.link_current(config, version), config)
    ssh_exec(host, Systemd.start(config, ports.new), config)
    wait_for_health!(host, config, ports.new, Keyword.get(opts, :rollback_version))
    reload_caddy(host, config, ports.new, Keyword.get(opts, :skip_hooks, true), context)
    stop_old_release(host, config, ports)
    enable_new_release(host, config, ports)
    ssh_exec(host, Caddy.write_active_port(config, ports.new), config)
    ports.new
  end

  # Bootstrap is the only other place the unit is written, so without this a
  # config change to it (drain_timeout, ssh.user, ...) never reached servers.
  # The new definition applies to the instance started next in this swap; the
  # serving instance keeps running.
  defp sync_unit(host, config) do
    case ssh_exec(host, Systemd.sync_unit(config), config) do
      {:ok, output} ->
        if output =~ "unit-updated" do
          say("  Updated systemd unit #{config.release.name}@.service on #{host}", :yellow)
        end

      {:error, reason} ->
        raise "Failed to update the systemd unit on #{host}: #{inspect(reason)}"
    end
  end

  # A release.name change would install a unit under the new name and then
  # stop instances that were never running, leaving the old-named instance
  # serving on its port and enabled for reboot. Stop before touching anything.
  defp refuse_renamed_release!(host, config) do
    case ssh_exec(host, Systemd.units_under_other_names(config), config) do
      {:ok, found} -> raise renamed_release_message(host, config, found)
      {:error, _} -> :ok
    end
  end

  @doc false
  def renamed_release_message(host, config, found) do
    old_names =
      found
      |> String.split("\n", trim: true)
      |> Enum.map(&(&1 |> Path.basename() |> String.replace_suffix("@.service", "")))

    ports = [config.caddy.app_port, Configuration.Caddy.alt_port(config.caddy)]

    cleanup =
      Enum.map_join(old_names, "\n", fn old ->
        instances = Enum.map_join(ports, " ", &"#{old}@#{&1}")

        "    sudo systemctl disable --now #{instances}\n" <>
          "    sudo rm /etc/systemd/system/#{old}@.service"
      end)

    """
    #{host} runs this app under a different release name (#{Enum.join(old_names, ", ")}), \
    but release.name is now #{inspect(config.release.name)}.

    Deploying would leave the old service running on its port and enabled on \
    reboot. Renaming a release is a migration: on #{host}, stop and remove the \
    old units, then bootstrap and deploy under the new name.

    #{cleanup}
        sudo systemctl daemon-reload

    Then run: mix xamal.server.bootstrap && mix xamal.deploy

    This takes the app down until the new deploy finishes.
    """
  end

  defp select_ports(host, config) do
    app_port = config.caddy.app_port
    alt_port = Configuration.Caddy.alt_port(config.caddy)
    active_port = read_active_port(host, config) || app_port
    new_port = if active_port == app_port, do: alt_port, else: app_port
    %{active: active_port, new: new_port}
  end

  defp wait_for_health!(host, config, new_port, rollback_version) do
    health_check = config.health_check
    delay = Configuration.readiness_delay(config)

    say(
      "  Waiting for health check (#{health_check.path}, timeout #{health_check.timeout}s)...",
      :magenta
    )

    Process.sleep(delay * 1000)

    case HealthCheck.wait_until_ready_remote(host, new_port, config,
           path: health_check.path,
           interval: health_check.interval,
           timeout: health_check.timeout
         ) do
      :ok ->
        say("  Health check passed on #{host}:#{new_port}", :green)

      {:error, :timeout} ->
        rollback_failed_boot(host, config, new_port, rollback_version)
        raise "Health check failed for #{host} after #{health_check.timeout}s"
    end
  end

  defp rollback_failed_boot(host, config, new_port, rollback_version) do
    say("  Health check timed out on #{host}:#{new_port}!", :red)
    ssh_exec(host, Systemd.stop(config, new_port), config)

    if rollback_version do
      ssh_exec(host, Server.link_current(config, rollback_version), config)
    end
  end

  defp reload_caddy(host, config, new_port, skip_hooks, context) do
    run_hook("pre-caddy-reload", [skip_hooks: skip_hooks], context)
    ssh_exec(host, Caddy.write_caddyfile(config, new_port), config)
    reload_caddy!(host, config)
    run_hook("post-caddy-reload", [skip_hooks: skip_hooks], context)
  end

  defp stop_old_release(host, config, %{active: active_port, new: new_port})
       when active_port != new_port do
    drain = Configuration.drain_timeout(config)
    say("  Stopping old release (#{drain}s drain timeout)...", :magenta)
    ssh_exec(host, Systemd.stop(config, active_port), config)
  end

  defp stop_old_release(_host, _config, _ports), do: :ok

  defp enable_new_release(host, config, %{active: active_port, new: new_port}) do
    ssh_exec(host, Systemd.enable(config, new_port), config)

    if active_port != new_port do
      ssh_exec(host, Systemd.disable(config, active_port), config)
    end
  end
end
