defmodule Xamal.Logs do
  @moduledoc false

  import Xamal.Output

  alias Xamal.Commands.Base
  alias Xamal.{Context, SSH}

  def parse_log_opts(args) do
    {log_opts, _, _} =
      OptionParser.parse(args,
        switches: [since: :string, lines: :integer, grep: :string, follow: :boolean],
        aliases: [n: :lines, f: :follow]
      )

    log_opts
  end

  def dispatch_logs(log_opts, build_cmd, config, opts, context) do
    hosts = Context.hosts(context)

    if Keyword.get(log_opts, :follow, false) do
      stream_logs(hd(hosts), build_cmd.(log_opts), config)
    else
      Enum.each(hosts, &print_logs(&1, build_cmd, log_opts, config, opts))
    end
  end

  defp stream_logs(host, cmd, config) do
    SSH.streaming_exec(host, Base.to_command_string(cmd), ssh_config: config.ssh)
  end

  defp print_logs(host, build_cmd, log_opts, config, opts) do
    type = Keyword.get(opts, :type, "App")
    cmd = build_cmd.(log_opts)

    case SSH.execute_command(host, cmd, ssh_config: config.ssh) do
      {:ok, output} -> puts_by_host(host_label(config, host), output, type: type)
      {:error, _} -> puts_by_host(host_label(config, host), "(no logs available)", type: type)
    end
  end
end
