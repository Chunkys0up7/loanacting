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
      "test.load": ["cmd --app loan_actor mix test --only load"],
      "test.smoke": ["cmd --app loan_actor mix test --only smoke"]
    ]
  end
end
