defmodule Mix.Tasks.Xamal.App.Start do
  @moduledoc "Starts the service on its active port without a full boot."
  @shortdoc "Starts the app"
  use Xamal.MixTask, run: {Xamal.AppTasks, :start}
end
