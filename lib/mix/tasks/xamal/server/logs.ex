defmodule Mix.Tasks.Xamal.Server.Logs do
  @moduledoc "Shows Caddy/proxy logs from the servers."
  @shortdoc "Shows server logs"
  use Xamal.MixTask, run: {Xamal.ServerTasks, :logs}
end
