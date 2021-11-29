defmodule SubscriptionsTransportWS.MixProject do
  use Mix.Project

  @url "https://github.com/maartenvanvliet/subscriptions-transport-ws"
  def project do
    [
      app: :subscriptions_transport_ws,
      version: "1.0.3",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @url,
      homepage_url: @url,
      name: "SubscriptionsTransportWS",
      description:
        "Implementation of the subscriptions-transport-ws graphql subscription protocol for Absinthe.",
      package: [
        maintainers: ["Maarten van Vliet"],
        licenses: ["MIT"],
        links: %{"GitHub" => @url},
        files: ~w(LICENSE README.md lib mix.exs .formatter.exs)
      ],
      docs: [
        main: "SubscriptionsTransportWS.Socket",
        canonical: "http://hexdocs.pm/subscriptions-transport-ws",
        source_url: @url,
        nest_modules_by_prefix: [SubscriptionsTransportWS]
      ],
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:absinthe, :phoenix_pubsub],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:absinthe_phoenix, "~> 2.0"},
      {:jason, "~> 1.1", optional: true},
      {:websocket_client, git: "https://github.com/jeremyong/websocket_client.git", only: :test},
      {:plug_cowboy, "~> 2.2", only: :test},
      {:ex_doc, "~> 0.23", only: [:dev, :test]},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
