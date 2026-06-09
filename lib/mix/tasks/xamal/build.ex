defmodule Mix.Tasks.Xamal.Build do
  @moduledoc "Builds the release tarball locally."
  @shortdoc "Builds release tarball"
  use Xamal.MixTask, run: {Xamal.BuildTasks, :build}
end
