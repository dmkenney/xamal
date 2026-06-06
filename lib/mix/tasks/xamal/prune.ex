defmodule Mix.Tasks.Xamal.Prune do
  @moduledoc "Removes old releases on selected hosts, keeping the retained count."
  @shortdoc "Prunes old releases"
  use Xamal.MixTask, run: {Xamal.Prune, :prune}
end
