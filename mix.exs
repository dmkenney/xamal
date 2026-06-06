defmodule Xamal.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/dmkenney/xamal"

  def project do
    [
      app: :xamal,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "_build/dev/dialyxir_plt.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ]
    ]
  end

  defp description do
    "Mix-first deployment tool for bare-metal Elixir releases over SSH. " <>
      "An Elixir port of Kamal using native releases, Caddy, and Elixir configuration."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md UPGRADING.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "UPGRADING.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Mix Tasks": [~r/Mix\.Tasks\.Xamal/]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :ssh, :inets],
      mod: {Xamal.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [ci: :test, "ci.lint": :test, "ci.test": :test]]
  end

  defp deps do
    [
      {:igniter, "~> 0.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      # Version-independent style and type checks. Run once in CI on the latest
      # Elixir; running them per-version adds cost without extra signal.
      "ci.lint": [
        "format --check-formatted",
        "credo --strict",
        "ex_dna",
        "reach.check --arch --smells",
        "dialyzer"
      ],
      # Version-dependent checks. Run across the full Elixir matrix in CI.
      "ci.test": [
        "compile --warnings-as-errors",
        "test"
      ],
      ci: ["ci.lint", "ci.test"]
    ]
  end
end
