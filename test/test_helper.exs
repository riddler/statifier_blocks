ExUnit.start()

# The LiveView tests mount a real connected view, which logs a MOUNT line
# carrying the whole session - a document struct - for every test. Useful once,
# unreadable eighty times over.
Logger.configure(level: :warning)

# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so the tests that drive it cannot run and are excluded by tag. The
# exclusion is derived from the dependency rather than from an env var, so a
# headless run and an ordinary run need no different command - and a
# misconfigured headless job that still has LiveView on the path runs the
# LiveView tests instead of silently skipping them.
if Code.ensure_loaded?(Phoenix.LiveView) do
  Application.put_env(:statifier_blocks, StatifierBlocks.EditorEndpoint,
    secret_key_base: String.duplicate("statifier_blocks_test_secret", 3),
    live_view: [signing_salt: "sb7f2salt"],
    server: false,
    url: [host: "localhost"]
  )

  {:ok, _pid} = StatifierBlocks.EditorEndpoint.start_link()
else
  ExUnit.configure(exclude: [:liveview])
end
