### Fixed

- The edit algebra's config gate refuses a `{:update_config, id, config}`
  whose value for a `{:type_expr, opts}` field is no arm that field admits,
  so the editor reports it where the edit is made rather than only at
  compile.
