defmodule Mix.Tasks.Xamal.Build.Upload do
  @moduledoc "Uploads the release tarball to target servers."
  @shortdoc "Uploads release tarball"
  use Xamal.MixTask, run: {Xamal.BuildTasks, :upload}
end
