defmodule Xamal.HealthCheck do
  @moduledoc """
  HTTP health check polling for deployment readiness.

  Polls a health check endpoint until it returns 200, or times out.
  """

  @doc """
  Poll a health check endpoint until it returns 200.

  Options:
  - path: the HTTP path (default "/health")
  - interval: seconds between checks (default 1)
  - timeout: max seconds to wait (default 30)
  - port: the port to check

  Returns :ok or {:error, :timeout}
  """
  def wait_until_ready(host, port, opts \\ []) do
    path = Keyword.get(opts, :path, "/health")
    interval = Keyword.get(opts, :interval, 1)
    timeout = Keyword.get(opts, :timeout, 30)

    deadline = System.monotonic_time(:second) + timeout
    url = "http://#{host}:#{port}#{path}"

    do_poll(url, interval, deadline)
  end

  @doc """
  Check health via SSH by curling from the remote server.
  Returns a command that can be executed remotely.
  """
  def check_command(port, path \\ "/health") do
    ["curl", "-sf", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:#{port}#{path}"]
  end

  @doc """
  Poll health check via SSH on a remote host.
  """
  def wait_until_ready_remote(host, port, config, opts \\ []) do
    path = Keyword.get(opts, :path, "/health")
    interval = Keyword.get(opts, :interval, 1)
    timeout = Keyword.get(opts, :timeout, 30)
    ssh_config = config.ssh

    deadline = System.monotonic_time(:second) + timeout
    cmd = check_command(port, path)

    do_poll_remote(host, cmd, ssh_config, interval, deadline)
  end

  defp do_poll(url, interval, deadline) do
    if System.monotonic_time(:second) > deadline do
      {:error, :timeout}
    else
      case http_get(url) do
        {:ok, 200} ->
          :ok

        _ ->
          Process.sleep(interval * 1000)
          do_poll(url, interval, deadline)
      end
    end
  end

  defp do_poll_remote(host, cmd, ssh_config, interval, deadline) do
    if System.monotonic_time(:second) > deadline do
      {:error, :timeout}
    else
      case Xamal.SSH.execute_command(host, cmd, ssh_config: ssh_config) do
        {:ok, "200"} ->
          :ok

        _ ->
          Process.sleep(interval * 1000)
          do_poll_remote(host, cmd, ssh_config, interval, deadline)
      end
    end
  end

  defp http_get(url) do
    case :httpc.request(:get, {~c"#{url}", []}, [timeout: 5000], []) do
      {:ok, {{_, status, _}, _headers, _body}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :connection_failed}
  end
end
