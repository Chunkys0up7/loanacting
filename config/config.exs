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
  # Foundation tool set (FT-043, contracts/tool-behaviour.md); test files may
  # override locally (Application.put_env) to inject fixtures instead.
  tools: [
    LoanActor.Tools.SetGoal,
    LoanActor.Tools.SatisfyGoal,
    LoanActor.Tools.RequestDocument,
    LoanActor.Tools.TransitionState,
    LoanActor.Tools.AppendNote,
    LoanActor.Tools.RequestOperatorApproval,
    LoanActor.Tools.VerifyDiaryChain
  ],
  # PII guard for tool args (FT-014 wired per constitution Principle VIII).
  tool_pii_guard: {LoanActor.PIIGuard, :apply}

config :logger, :default_formatter,
  format: "$time [$level] $message $metadata\n",
  metadata: [:loan_id, :sequence, :event_id, :request_id]

import_config "#{config_env()}.exs"
