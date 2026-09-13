### Changed

- A `core.on_event` `capture` literal carrying a raw control character other
  than tab, line feed or carriage return is now refused at compile, on the
  `capture` key, because the value reaches an XML attribute raw and XML 1.0
  admits no such character there.
