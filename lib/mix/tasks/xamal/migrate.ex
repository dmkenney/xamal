defmodule Mix.Tasks.Xamal.Migrate do
  @moduledoc """
  Runs the release migrator on the selected hosts.

  Calls `<AppModule>.Release.migrate()` by convention. Pass a module to override:

      mix xamal.migrate MyApp.Release
  """
  @shortdoc "Runs the release migrator"
  use Xamal.MixTask, run: {Xamal.AppTasks, :migrate}
end
