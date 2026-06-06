defmodule Mix.Tasks.Xamal.App.StaleReleases do
  @moduledoc "Lists releases that pruning would remove (read-only preview)."
  @shortdoc "Lists prunable releases"
  use Xamal.MixTask, run: {Xamal.AppTasks, :stale_releases}
end
