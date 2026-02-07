defmodule Xamal.SSH.Runner do
  @moduledoc """
  Parallel execution runner with configurable concurrency.

  Uses Task.async_stream with complete-all semantics (collects all
  results, doesn't fail-fast).
  """

  @doc """
  Run a function on each host in parallel.

  Options:
  - concurrency: max parallel tasks (default: unlimited)
  - wait: seconds to wait between batches (default: nil)
  - timeout: per-task timeout in ms (default: 60_000)

  Returns a list of {host, result} tuples.
  """
  def run(hosts, fun, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency)
    wait = Keyword.get(opts, :wait)
    timeout = Keyword.get(opts, :timeout, 60_000)

    if concurrency do
      run_with_limit(hosts, fun, concurrency, wait, timeout)
    else
      run_unlimited(hosts, fun, timeout)
    end
  end

  defp run_unlimited(hosts, fun, timeout) do
    hosts
    |> Task.async_stream(fn host -> {host, fun.(host)} end,
      timeout: timeout,
      ordered: true,
      on_timeout: :kill_task
    )
    |> collect_results()
  end

  defp run_with_limit(hosts, fun, concurrency, wait, timeout) do
    hosts
    |> Enum.chunk_every(concurrency)
    |> Enum.with_index()
    |> Enum.flat_map(fn {batch, index} ->
      if index > 0 and wait do
        Process.sleep(wait * 1000)
      end

      batch
      |> Task.async_stream(fn host -> {host, fun.(host)} end,
        timeout: timeout,
        ordered: true,
        on_timeout: :kill_task
      )
      |> collect_results()
    end)
  end

  defp collect_results(stream) do
    Enum.map(stream, fn
      {:ok, {host, result}} -> {host, result}
      {:exit, reason} -> {nil, {:error, reason}}
    end)
  end
end
