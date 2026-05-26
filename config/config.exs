import Config

config :loan_actor,
  # Heartbeat interval for the periodic loop (per spec SC-011 test override)
  heartbeat_ms: 60_000,
  # Production must have a real operator id; tests can disable
  require_operator_id: true,
  # Diary store implementation; swap for tests / experiments
  diary_store: LoanActor.Diary.Mnesia,
  # Mnesia directory (per-env override below)
  mnesia_dir: "priv/mnesia",
  # Subscriber bounded queue size before slow-client resync (research R-2)
  ag_ui_subscriber_buffer: 128

config :logger, :default_formatter,
  format: "$time [$level] $message $metadata\n",
  metadata: [:loan_id, :sequence, :event_id, :request_id]

import_config "#{config_env()}.exs"
