defmodule Mix.Tasks.Xamal.App.Version do
  @moduledoc "Prints the current release version on each host."
  @shortdoc "Shows the deployed version"
  use Xamal.MixTask, run: {Xamal.AppTasks, :version}
end
