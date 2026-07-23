# Load/performance tests are tagged :load and run via `mix test.load`
# (`mix test --only load`). Default runs exclude them.
#
# FT-036's diary scale test is tagged :slow and run via `mix test.slow`
# (nightly in CI, not on every push/PR — see ci-nightly.yml) for the same
# reason: seeding + replaying 1,000,000 entries is far too slow for the
# per-PR gate.
ExUnit.start(exclude: [:load, :slow])
