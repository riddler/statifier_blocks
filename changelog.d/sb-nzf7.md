### Changed

- `StatifierBlocks.Describe.render/2` sets a delayed `core.send`'s sentence in double quotation marks wherever an edge line embeds it, so its own comma no longer reads as the line's: `The steps start with "In 7 days, send loan.overdue"`, `After "In 7 days, send loan.overdue" (done), Wait 14d`. The send's node line, an undelayed send and every other step read as before. A host that matched the old edge lines reads the new words or rewords them through `StatifierBlocks.Describe.Phrasing`.
