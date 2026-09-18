### Fixed

- A declared slot whose child count violates its declared arity now draws a
  `:slot_arity_violated` finding even when the composite carrying it declares
  no outcomes; it used to compile green with the declaration's refusal lost.
