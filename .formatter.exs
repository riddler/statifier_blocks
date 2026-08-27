# Used by "mix format"
#
# `phoenix_live_view` is imported for its HEEx formatter plugin and its
# `attr`/`slot` locals. It is an optional dependency (ADR-0005 decision 1) and
# `import_deps` on a dependency that is absent is an error, so the import is
# conditional on the dependency actually being there - which is exactly the
# headless tree the record's CI job resolves.
live_view? = File.dir?(Path.join(Mix.Project.deps_path(), "phoenix_live_view"))

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: if(live_view?, do: [:phoenix_live_view], else: []),
  plugins: if(live_view?, do: [Phoenix.LiveView.HTMLFormatter], else: [])
]
