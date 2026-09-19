# RSpec: pending vs skip

Test exclusions require evidence. Missing instructions, missing Ruby support, a broken test, or difficulty making
a faithful port pass do not justify disabling an in-scope test. Implement or fix the behavior and its prerequisites.
If an external blocker remains, report it accurately without claiming the feature or issue is complete.

## What the mechanisms do

- `pending` inside an example allows execution to continue and expects a failure. An unexpected pass fails the
  suite so the obsolete pending declaration can be removed or narrowed.
- `skip` stops execution of the example; code after it is not exercised.
- Empty examples, `xit`/`xdescribe`, exclusion metadata, early returns, and broad rescue blocks can also hide
  coverage. They are subject to the same policy; changing syntax does not make an exclusion acceptable.

RSpec does not match a pending reason against the actual exception. A pending example can hide an unrelated
failure. Read its failure output and verify the cause, not just the suite's exit status.

## Verified external failures: pending

Use `pending` for a reproduced external browser/protocol defect when the test can still run. Before adding or
retaining it for affected work:

1. Run the example without the declaration, or inspect a reproducible failure from the same environment. Identify
   the failing operation and actual error/assertion. Missing Ruby methods and unrelated setup failures are not
   evidence of a browser limitation.
2. Read the upstream test and its expectation conditions at the chosen ref, plus the relevant browser issue/status.
   Record the browser version, protocol, operating system, and mode where relevant. A Linux-only expectation must
   not become an unconditional Firefox exclusion; an old issue does not prove the current browser still fails.
3. Record the upstream source/expectation link, external issue, observed failure, affected conditions, and condition
   for rechecking/removal in the test comment and PR evidence. Prefer pinned source links for reproducibility.
4. Apply the smallest supported condition to the individual example and keep its full setup, actions, assertions,
   and cleanup. If the affected range is unknown, report that uncertainty rather than inventing a version gate or
   generalizing one observation to all browsers/platforms.
5. Review the pending failure output on subsequent relevant runs. Unexpected errors still need investigation;
   broad `pending` is not permission to accept any failure.

On an unexpected pass, recheck the behavior and remove or narrow the obsolete declaration. Do not replace it with
`skip`, delete assertions, force a new failure, or swallow errors to restore a green run.

## Justified exclusions: skip

Use `skip` only when execution itself is inapplicable or cannot meaningfully proceed under a documented condition,
such as an upstream test restricted to a different operating system or a genuinely unavailable optional external
service. Scope the condition to the affected example/environment and explain it in the port's mapping.

An existing placeholder for an explicitly deferred, out-of-scope feature may remain identified as such. It is not
evidence of implemented behavior, and it must not be copied as the implementation of a newly requested in-scope
feature. CDP-only tests need no Ruby port in this BiDi-only project; document their exclusion rather than creating
empty examples to inflate test totals.

When retaining a skipped example, preserve its full body so it can run when the condition changes. Do not use a
suite-wide hook to hide unaffected cases. Local browser launch failures or missing tools should be fixed where
feasible; otherwise report the check as unrun/blocked instead of committing a skip to accommodate one workstation.

## Completion and review

List pending, skipped, and unrun cases separately from passing tests, with their reasons and conditions. Reconcile
new and changed exclusions against the upstream tests and requested scope before claiming completion. Review any
deleted assertion or test body as a potential lost regression, even if example counts are unchanged.

For the complete workflow, see [porting Puppeteer](porting_puppeteer.md) and
[upstream test fidelity](testing_strategy.md#upstream-test-fidelity).

## References

- [RSpec pending and skipped examples](https://rspec.info/features/3-13/rspec-core/pending-and-skipped-examples/)
- [WebDriver BiDi specification](https://w3c.github.io/webdriver-bidi/) defines protocol behavior, not a browser's
  current implementation status. Verify browser support using version-specific evidence and actual test results.
