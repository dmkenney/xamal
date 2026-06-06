defmodule Mix.Tasks.Xamal.Iex do
  @moduledoc "Opens an interactive remote IEx session on the running release."
  @shortdoc "Opens a remote IEx session"
  use Xamal.MixTask, run: {Xamal.AppTasks, :iex}
end
