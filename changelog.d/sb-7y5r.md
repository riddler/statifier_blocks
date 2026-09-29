### Added

- `StatifierBlocks.Describe.Node` carries `noun`, the name an edge line gives the block when it is the edge's container: its title, else a short noun for its type, and `nil` for a block with no slots or one the palette cannot resolve.

### Changed

- `StatifierBlocks.Describe.render/2` names a container by a noun in its edge lines rather than by its sentence: its title where it has one, else a short noun for its type (`The steps start with Wait 14d`, `Send loan.overdue (done) ends the steps`, `abandons the group`); a host's container reads `the` and its palette label in lower case. Node lines, and a step named in an edge line, keep their sentence. A host that matched the old edge lines reads the new words or rewords them through `StatifierBlocks.Describe.Phrasing`.
