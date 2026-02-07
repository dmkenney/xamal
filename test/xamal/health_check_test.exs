defmodule Xamal.HealthCheckTest do
  use ExUnit.Case, async: true

  alias Xamal.HealthCheck

  describe "check_command/2" do
    test "builds curl command for health check" do
      cmd = HealthCheck.check_command(4000, "/health")
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "curl"
      assert cmd_str =~ "4000"
      assert cmd_str =~ "/health"
    end

    test "uses default path" do
      cmd = HealthCheck.check_command(4001)
      cmd_str = Enum.join(cmd, " ")

      assert cmd_str =~ "/health"
    end
  end

  describe "wait_until_ready/3" do
    test "times out when service is not available" do
      # Use a port that's very unlikely to be listening
      result = HealthCheck.wait_until_ready("127.0.0.1", 19999, timeout: 1, interval: 1)
      assert result == {:error, :timeout}
    end
  end
end
