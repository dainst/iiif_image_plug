defmodule IIIFImagePlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :iiif_image_plug,
      version: "0.2.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        ignore_modules: [
          DevCallbacks,
          DevServer,
          DevServerPlug
        ]
      ],
      name: "IIIFImagePlug",
      source_url: "https://github.com/dainst/iiif_image_plug",
      description: "An Elixir Plug implementing the IIIF image API specification.",
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod:
        if Mix.env() in [:dev, :test] do
          {DevServer, []}
        else
          []
        end,
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.16"},
      {:vix, "~> 0.33.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6", only: [:test, :dev]},
      {:image, "~> 0.59.0", only: [:test]},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE* CHANGELOG* ),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/dainst/iiif_image_plug",
        "International Image Interoperability Framework" => "https://iiif.io/"
      }
    ]
  end

  defp docs() do
    [
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ]
    ]
  end
end
