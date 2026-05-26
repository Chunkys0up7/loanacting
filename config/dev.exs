import Config

config :loan_actor,
  heartbeat_ms: 5_000,
  require_operator_id: false,
  mnesia_dir: "priv/mnesia_dev"

config :logger, level: :debug
