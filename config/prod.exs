import Config

config :loan_actor,
  require_operator_id: true,
  mnesia_dir: "/var/lib/loan_actor/mnesia"

config :logger, level: :info
