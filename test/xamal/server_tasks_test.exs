defmodule Xamal.ServerTasksTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration
  alias Xamal.ServerTasks

  defp config(app_port \\ 4000) do
    %Configuration{caddy: %Configuration.Caddy{app_port: app_port}}
  end

  describe "caddy_upstream_port/2" do
    test "uses app_port on a fresh server with no active_port file" do
      # read_active_port/2 returns nil when the file is absent; nothing is
      # running yet, so the configured port is the only sensible upstream.
      assert ServerTasks.caddy_upstream_port(nil, config()) == 4000
    end

    test "keeps the live port when the server is on alt_port" do
      # The regression: bootstrap re-run against a server whose last deploy
      # landed on 4001 used to write 4000 and reload Caddy, pointing it at the
      # idle port.
      assert ServerTasks.caddy_upstream_port(4001, config()) == 4001
    end

    test "keeps the live port when the server is on app_port" do
      assert ServerTasks.caddy_upstream_port(4000, config()) == 4000
    end

    test "falls back to app_port when active_port is not a blue-green port" do
      # A truncated or hand-edited active_port file must not become an upstream.
      assert ServerTasks.caddy_upstream_port(9999, config()) == 4000
      assert ServerTasks.caddy_upstream_port(0, config()) == 4000
    end

    test "tracks a non-default app_port" do
      assert ServerTasks.caddy_upstream_port(8081, config(8080)) == 8081
      assert ServerTasks.caddy_upstream_port(4001, config(8080)) == 8080
    end
  end
end
