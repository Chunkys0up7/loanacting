defmodule LoanAsActor.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      apps: [:loan_actor],
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: ["test.load": :test, "test.smoke": :test],
      dialyzer: [
        plt_add_apps: [:mnesia, :ex_unit, :mix],
        flags: [:error_handling, :unknown, :unmatched_returns, :no_opaque]
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # `cmd --app loan_actor mix test ...` (the original form) `File.cd!`s
      # into apps/loan_actor and runs a SEPARATE mix invocation scoped to
      # that app's own mix.exs — whose deps() doesn't list credo/dialyxir
      # (root-only deps, declared above). Several loan_actor test files
      # `Code.require_file` a lib/credo/checks/*.ex module directly (it's
      # excluded from elixirc_paths so prod builds don't need Credo), which
      # does `use Credo.Check` — found via FT-035's own load test: that
      # require failed with "module Credo.Check is not loaded" under the
      # scoped form, since Credo was never a dep of the sub-invocation.
      # Running from the umbrella root (deps declared here) has full access
      # to both this project's deps AND loan_actor's.
      "test.load": ["test --only load"],
      "test.smoke": ["test --only smoke"]
    ]
  end
end
