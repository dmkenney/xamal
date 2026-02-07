defmodule Xamal.SSH.RunnerTest do
  use ExUnit.Case, async: true

  alias Xamal.SSH.Runner

  describe "run/3" do
    test "executes function on all hosts" do
      hosts = ["host1", "host2", "host3"]
      results = Runner.run(hosts, fn host -> String.upcase(host) end)

      assert length(results) == 3
      assert {"host1", "HOST1"} in results
      assert {"host2", "HOST2"} in results
      assert {"host3", "HOST3"} in results
    end

    test "respects concurrency limit" do
      # Use a shared agent to track concurrent executions
      {:ok, agent} = Agent.start_link(fn -> {0, 0} end)

      hosts = Enum.map(1..6, &"host#{&1}")

      Runner.run(
        hosts,
        fn host ->
          Agent.update(agent, fn {current, max} ->
            new_current = current + 1
            {new_current, max(max, new_current)}
          end)

          Process.sleep(50)

          Agent.update(agent, fn {current, max} ->
            {current - 1, max}
          end)

          host
        end,
        concurrency: 2
      )

      {_current, max_concurrent} = Agent.get(agent, & &1)
      Agent.stop(agent)

      assert max_concurrent <= 2
    end

    test "waits between batches" do
      start = System.monotonic_time(:millisecond)

      hosts = ["host1", "host2", "host3", "host4"]

      Runner.run(hosts, fn host -> host end, concurrency: 2, wait: 1)

      elapsed = System.monotonic_time(:millisecond) - start
      # Should have waited ~1 second between the two batches
      assert elapsed >= 900
    end
  end
end
