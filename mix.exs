defmodule Xamal.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :xamal,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Xamal.CLI],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :ssh, :eex, :inets],
      mod: {Xamal.Application, []}
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"}
    ]
  end
end
