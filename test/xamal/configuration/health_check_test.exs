defmodule Xamal.Configuration.HealthCheckTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.HealthCheck

  describe "new/1" do
    test "parses health check config" do
      hc = HealthCheck.new(%{"path" => "/ready", "interval" => 2, "timeout" => 60})

      assert hc.path == "/ready"
      assert hc.interval == 2
      assert hc.timeout == 60
    end

    test "defaults" do
      hc = HealthCheck.new(%{})

      assert hc.path == "/health"
      assert hc.interval == 1
      assert hc.timeout == 30
    end

    test "handles nil config" do
      hc = HealthCheck.new(nil)

      assert hc.path == "/health"
      assert hc.interval == 1
      assert hc.timeout == 30
    end
  end
end
