### Changed

- `core.send` now emits its `<send>` with `id="<the block's state id>__send"`, so a delayed send can be named after it is armed.
- A delayed `core.send` is now cancelled by its scope: the compiler emits `<cancel sendid="..."/>` in the `<onexit>` of the nearest enclosing block's state, so a pending send does not outlive the sequence or group that armed it. Charts containing a delayed `core.send` change bytes; every other chart is unchanged, `core.wait` timers included.
