defmodule Makrinos.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project, do: [
    app: :makrinos,
    version: @version,
    elixir: "~> 1.7",
    start_permanent: Mix.env() == :prod,
    deps: deps(),

    description: description(),
    package: package(),
    name: "Makrinos",
    source_url: "https://github.com/tsutsu/makrinos",
    docs: docs()
  ]

  defp description do
    """
    An efficient Elixir JSON-RPC client with support for multiple transports
    """
  end

  defp package, do: [
    name: :makrinos,
    files: ["lib", "mix.exs", "README.md", "LICENSE"],
    maintainers: ["Levi Aul"],
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/tsutsu/makrinos"}
  ]

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
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp docs, do: [
    source_ref: "v#\{@version\}",
    canonical: "https://hexdocs.pm/makrinos",
    main: "readme",
    extras: ["README.md"],
    groups_for_extras: [
      "Readme": Path.wildcard("*.md")
    ]
  ]
end
