defmodule Makrinos.MixProject do
  use Mix.Project

  def project do
    [
      app: :makrinos,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Makrinos.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.1"},
      {:machine_gun, "~> 0.1.2"},
      {:procket, "~> 0.9.3"}
    ]
  end
end
