defmodule StatifierBlocks.MixProject do
  use Mix.Project

  @version "0.17.0"
  @source_url "https://github.com/riddler/statifier_blocks"

  # ADR-0005 decision 1's acceptance property: the package must compile clean
  # and its non-LiveView suite must pass with `phoenix_live_view` absent from
  # the dependency tree. `STATIFIER_BLOCKS_HEADLESS=1` is how that tree is
  # produced. It drops the optional dependency *and* redirects the deps,
  # build and lock paths to headless-only siblings, so resolving a
  # Phoenix-free tree can never disturb the ordinary one - in particular it
  # can never rewrite `mix.lock`, which a plain `mix deps.get` with the
  # dependency removed absolutely would.
  @headless System.get_env("STATIFIER_BLOCKS_HEADLESS") in ["1", "true"]

  def project do
    [
      app: :statifier_blocks,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps_path: if(@headless, do: "deps_headless", else: "deps"),
      build_path: if(@headless, do: "_build_headless", else: "_build"),
      lockfile: if(@headless, do: "mix.headless.lock", else: "mix.lock"),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "StatifierBlocks",
      description:
        "Block document model, one-way SCXML compiler, and LiveView editor components for composing Statifier statecharts",
      source_url: @source_url,
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:ex_unit]],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Hexdocs configuration. These paths are read off the publisher's disk at
  # `mix docs` time and need no entry in package()'s files: list - the docs
  # tarball hexdocs hosts is built separately from the package tarball
  # `mix deps.get` fetches.
  defp docs do
    [
      name: "StatifierBlocks",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/statifier_blocks",
      source_url: @source_url,
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      # Without this the first hexdocs is one flat list of ~50 modules, which
      # tells a reader nothing about which of them they are meant to call. The
      # groups follow the package's own seams - the document is the source of
      # truth, block types are the extension seam, the compiler is one way, and
      # the editor is the optional LiveView half - so the sidebar reads as the
      # architecture rather than as the alphabet. Order matters: ex_doc assigns
      # each module to the first group whose pattern matches.
      groups_for_modules: [
        "Document model": [
          ~r/^StatifierBlocks\.(Document|Block|Id|CanonicalJson|Decode|Validation|SlotValidation)($|\.)/
        ],
        "Block types and assignability": [
          ~r/^StatifierBlocks\.(BlockType|Palette|Assignability)($|\.)/
        ],
        "Core block vocabulary": [
          ~r/^StatifierBlocks\.Core($|\.)/
        ],
        Compiler: [
          ~r/^StatifierBlocks\.(Compiler|Compiled|CompilationRecord|Emission|Provenance)($|\.)/
        ],
        "Edit algebra and view model": [
          ~r/^StatifierBlocks\.(Edit|Finding|ViewModel)($|\.)/
        ],
        "LiveView editor": [
          ~r/^StatifierBlocks\.Editor($|\.)/
        ],
        "Predicate evaluation": [
          ~r/^StatifierBlocks\.Predicates($|\.)/
        ]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      name: "statifier_blocks",
      licenses: ["MIT"],
      # `assets` is in the list because the hook and the stylesheet ship as
      # source (ADR-0005 decisions 7 and 14, sui-ADR-0009's delivery model),
      # and source that is not in the tarball is not public API however
      # carefully it is versioned. The record calls this out by name.
      files: ~w(lib assets mix.exs README.md LICENSE CHANGELOG.md),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [statifier_dep()] ++
      live_view_dep() ++
      [
        # Direct because `StatifierBlocks.Core.Duration` calls
        # `Predicator.Duration.parse/1` to read a stored predicator duration
        # string. It already resolves through statifier, so naming it here
        # records the call rather than moving the lock.
        #
        # The floor is 9.0 and not 9.2 deliberately. Every predicator module
        # this package names - `Predicator.Duration`, `Predicator.evaluate/2`,
        # `Predicator.Errors.*`, `Predicator.Lexer` - shipped in 9.0.0. The
        # 9.2 module is `Predicator.Simple`, and nothing here calls it:
        # statifier-ui does, statifier-ui requires `~> 9.2` itself, and
        # statifier-ui is *optional* here. So a host that takes this package
        # without the expression editor needs only 9.0, and a host that takes
        # the editor is driven to 9.2 by statifier-ui's own requirement,
        # which is how a transitive requirement is supposed to work. Raising
        # the floor here would overstate what this package needs.
        {:predicator, "~> 9.0"},
        # Dev / test
        {:ex_quality, "~> 0.14", only: :dev, runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.18", only: :test},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false}
      ]
  end

  # ADR-0005 decision 1. The requirement and the flag are copied deliberately
  # from statifier-ui's `mix.exs`: two packages in one family disagreeing
  # about the LiveView floor is a problem a host discovers at dependency
  # resolution, and there is no reason to create it. No `phoenix_html`,
  # `esbuild` or `tailwind` - the first arrives transitively, the other two
  # belong to the host (sui-ADR-0009).
  #
  # The empty list is the headless tree, and it is the only place in this
  # file that decides whether the guard around `StatifierBlocks.Editor.*`
  # has anything to guard.
  # `lazy_html` rides along because `Phoenix.LiveViewTest` refuses to run
  # without it. It is `only: :test` and never reaches a host, and it belongs in
  # this list rather than beside the other test dependencies precisely because
  # it is useless in the headless tree - nothing there drives a LiveView.
  defp live_view_dep do
    if @headless do
      []
    else
      [
        {:phoenix_live_view, "~> 1.0", optional: true},
        # sb-m6e0: an `:expression` field renders statifier-ui's expression
        # editor when this resolves, and the plain source input when it does
        # not, so the dependency is optional in the same sense LiveView is
        # and `StatifierBlocks.Editor.Field` guards on it the same way.
        #
        # It belongs in this list rather than beside the unconditional
        # dependencies because its only consumer is a LiveView component:
        # the headless tree has no editor to render, so pulling it there
        # would resolve a package nothing in that tree can call.
        {:statifier_ui, "~> 0.4", optional: true},
        {:lazy_html, ">= 0.1.0", only: :test}
      ]
    end
  end

  # Export STATIFIER_PATH to point at a local checkout while co-developing a
  # change that spans both repos. It is an env var rather than a mix.exs edit
  # so the override never lands in a commit by accident.
  defp statifier_dep do
    case System.get_env("STATIFIER_PATH") do
      nil -> {:statifier, "~> 2.2"}
      path -> {:statifier, path: path, override: true}
    end
  end
end
