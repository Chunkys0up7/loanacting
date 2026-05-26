defmodule LoanActor.MixProject do
  use Mix.Project

  def project do
    [
      app: :loan_actor,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "test.load": :test,
        "test.smoke": :test
      ]
    ]
  end

  def application do
    [
      mod: {LoanActor.Application, []},
      extra_applications: [:logger, :crypto, :mnesia]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP layer
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},

      # Identity
      {:uniq, "~> 0.6"},

      # Observability
      {:telemetry, "~> 1.2"},

      # Test + property-based
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: [:dev, :test]}
    ]
  end
end
