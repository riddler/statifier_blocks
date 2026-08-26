defmodule StatifierBlocks.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/riddler/statifier_blocks"

  def project do
    [
      app: :statifier_blocks,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "StatifierBlocks",
      description:
        "Block document model, one-way SCXML compiler, and LiveView editor components for composing Statifier statecharts",
      source_url: @source_url,
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "statifier_blocks",
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE),
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  # Scaffold-only dependency set. The quality tooling (ex_quality, credo,
  # dialyxir, excoveralls), the docs tooling (ex_doc), and the LiveView
  # dependencies the editor components need are added by the beads that
  # follow this one in the bootstrap stack.
  defp deps do
    [
      statifier_dep()
    ]
  end

  # Export STATIFIER_PATH to point at a local checkout while co-developing a
  # change that spans both repos. It is an env var rather than a mix.exs edit
  # so the override never lands in a commit by accident.
  defp statifier_dep do
    case System.get_env("STATIFIER_PATH") do
      nil -> {:statifier, "~> 2.0"}
      path -> {:statifier, path: path, override: true}
    end
  end
end
