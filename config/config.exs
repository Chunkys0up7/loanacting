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
  ag_ui_subscriber_buffer: 128,
  # LoanActor.Web.Endpoint (FT-027) port; per-env override below
  http_port: 4000,
  # Foundation tool set (FT-043, contracts/tool-behaviour.md); test files may
  # override locally (Application.put_env) to inject fixtures instead.
  # Decision-harness tools (intent 0003, ADH-002+) appended below.
  tools: [
    LoanActor.Tools.SetGoal,
    LoanActor.Tools.SatisfyGoal,
    LoanActor.Tools.RequestDocument,
    LoanActor.Tools.TransitionState,
    LoanActor.Tools.AppendNote,
    LoanActor.Tools.RequestOperatorApproval,
    LoanActor.Tools.VerifyDiaryChain,
    LoanActor.Tools.AssessLoan
  ],
  # PII guard for tool args (FT-014 wired per constitution Principle VIII).
  tool_pii_guard: {LoanActor.PIIGuard, :apply}

config :logger, :default_formatter,
  format: "$time [$level] $message $metadata\n",
  metadata: [:loan_id, :sequence, :event_id, :request_id]

# Found via FT-035's load test (NFR-001, 100 concurrent loans / 10
# events/sec/loan): Mnesia's OTP default (100) triggers "Mnesia is
# overloaded: {:dump_log, :write_threshold}" well before that write
# volume, throttling writers hard enough to blow past the 100ms p95
# budget (observed: a GenServer.call outright timing out at 5s under the
# full 100-loan profile). Raising the threshold is standard Mnesia
# tuning for write-heavy workloads — it only changes how often the
# internal transaction log gets consolidated into the base table files
# (a throughput/latency tradeoff), not any durability guarantee: a
# committed write is still durable regardless of this value. Read at
# Mnesia application startup, so this must be `config`, not
# `Application.put_env/3` after the fact.
config :mnesia, dump_log_write_threshold: 50_000

import_config "#{config_env()}.exs"
