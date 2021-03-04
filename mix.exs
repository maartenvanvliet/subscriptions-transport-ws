defmodule SubscriptionsTransportWs.MixProject do
  use Mix.Project

  @url "https://github.com/maartenvanvliet/subscriptions-transport-ws"
  def project do
    [
      app: :subscriptions_transport_ws,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @url,
      homepage_url: @url,
      name: "SubscriptionsTransportWS",
      description: "SubscriptionsTransportWS",
      package: [
        maintainers: ["Maarten van Vliet"],
        licenses: ["MIT"],
        links: %{"GitHub" => @url},
        files: ~w(LICENSE README.md lib mix.exs)
      ],
      docs: [
        main: "SubscriptionsTransportWs.Socket",
        canonical: "http://hexdocs.pm/quarto",
        source_url: @url
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
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
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end
end
