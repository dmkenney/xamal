defmodule Mix.Tasks.Xamal.Version do
  @moduledoc "Prints the installed Xamal version."
  @shortdoc "Prints the Xamal version"
  use Mix.Task

  @impl true
  def run(_args), do: Mix.shell().info("Xamal #{Xamal.version()}")
end
