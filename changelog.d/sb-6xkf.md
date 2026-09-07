### Added

- `ViewModel.transparent?/2`, `effective_parent/3` and `end_of_list_target/3`
  answer where a row sits and where an append lands once a host has flattened
  its transparent containers, taking the transparent type names as an argument.
- `ViewModel.core_containers/0` names the three core containers a host most
  often flattens, as the documented default for those readers rather than a
  built-in policy.
