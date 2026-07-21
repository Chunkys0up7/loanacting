defmodule LoanActor.Tools.VerifyDiaryChain do
  @moduledoc """
  Requests a diary chain integrity check (FT-043; periodic loop). Returns
  the effect `%{verify_chain: true}` — deliberately an INTENT, not a real
  call to `DiaryStore.verify_chain/1` — since `Tool.Context` carries no
  store reference (tools stay pure functions of `(args, ctx)`; the Server
  has the I/O access and applies this effect by actually running the
  verification and diary-logging the result).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "verify_diary_chain",
      description: "Request a diary chain integrity check.",
      parameters: %{"type" => "object"}
    })
  end

  @impl LoanActor.Tool
  def execute(_args, _ctx), do: {:ok, %{verify_chain: true}}
end
