### Changed

- The Map draws the happy path straight through a group whose body holds a
  container, such as a branch: the Map hook lays that document out twice,
  the second time with the group's edges attached where its body's steps
  stand, instead of at the middle of the group.
