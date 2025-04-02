defmodule IIIFImagePlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :iiif_image_plug,
      version: "0.3.1",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        ignore_modules: [
          DevServerHelper,
          DevServer,
          DevServerRouter
        ]
      ],
      name: "IIIFImagePlug",
      source_url: "https://github.com/dainst/iiif_image_plug",
      description: "An Elixir Plug implementing the IIIF image API specification.",
      deps: deps(),
      package: package(),
      docs: docs(),
      aliases: aliases()
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
      {:cors_plug, "~> 3.0", only: [:test, :dev]},
      {:image, "~> 0.59.0", only: [:test]},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* ),
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
        "additional_docs/performance_considerations.md": [title: "Performance considerations"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ]
    ]
  end

  defp aliases do
    [docs: ["docs", &copy_doc_images/1]]
  end

  defp copy_doc_images(_) do
    # Images can not be added to the `:extras` in `docs()`. Instead we have to copy them
    # manually to the `doc/` directory generated when running `mix hex.publish`.
    File.cp!("additional_docs/image_pyramid.png", "doc/image_pyramid.png")
  end
end
