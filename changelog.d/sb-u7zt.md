### Added

- Write signatures across the `core.*` vocabulary, so the environment
  survives one. `core.assign` writes its `path` and `core.subchart` its
  `assign_to` as known-but-untyped; `core.map` writes `collect` as
  `{:list, :unknown}`, so the block after a fan-out knows it is looking at a
  list; `core.on_event` writes one path per `capture` pair on the interrupt
  path; `core.wait`, `core.send`, `core.raise` and `core.await` write nothing
  and leave the environment exactly as it reached them; and a container hands
  its children's writes out through the per-path merge.
