defmodule Mix.Tasks.Xamal.Shell do
  @moduledoc "Opens an interactive remote shell on the running release."
  @shortdoc "Opens a remote shell"
  use Xamal.MixTask, run: {Xamal.AppTasks, :shell}
end
