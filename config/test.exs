import Config

config :loan_actor,
  # Fast heartbeat so SC-011 cadence test completes quickly
  heartbeat_ms: 100,
  require_operator_id: false,
  # File-backed diary by default in tests; Mnesia integration tests override
  diary_store: LoanActor.Diary.File,
  mnesia_dir: "priv/mnesia_test",
  # Tighter buffer to exercise slow-client resync (research R-2)
  ag_ui_subscriber_buffer: 8

config :logger, level: :warning
