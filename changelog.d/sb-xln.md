### Changed

- Every illustrative example in the package - ADR worked examples, doc examples, and the shipped fixture bundles - now uses one of the family's two canonical example domains: credit-card authorization and capture, or a signup wizard with A/B testing.
- `StatifierBlocks.Core.Branch.fixtures/0` ships budget-decision datasets (`"approved"` / `"declined"`) and the expression `"budget_remaining > amount"` in place of its previous lead-scoring bundle. A host rendering the bundle in a palette panel sees the new names.
- The arm-slot and lane-name validation messages on `core.branch` and `core.parallel` name `"arm_approved"` and `"capture"` as their exemplars rather than the previous ones. The rules they describe are unchanged.
