defmodule IIIFImagePlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :iiif_image_plug,
      version: "0.7.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        ignore_modules: [
          BehindProxyPlug,
          CachingPlug,
          ContentTypeOverridePlug,
          Custom404Plug,
          CustomResponseHeaderPlug,
          CustomRequestErrorPlug,
          DefaultPlug,
          DevServer,
          DevServerRouter,
          ExtraInfoPlug
        ]
      ],
      name: "IIIFImagePlug",
      source_url: "https://codeberg.org/dainst/iiif_image_plug",
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
      {:plug, "~> 1.19"},
      {:vix, "~> 0.36.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6", only: [:test, :dev]},
      {:cors_plug, "~> 3.0", only: [:test, :dev]},
      {:image, "~> 0.59.0", only: [:test]},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* ),
      licenses: ["Apache-2.0"],
      links: %{
        "International Image Interoperability Framework" => "https://iiif.io/",
        "Elixir Forum" =>
          "https://elixirforum.com/t/iiif-image-plug-an-elixir-plug-implementing-the-iiif-image-api-specification/",
        "GitHub" => "https://github.com/dainst/iiif_image_plug"
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

  defp aliases do
    [docs: ["docs", &copy_doc_images/1]]
  end

  defp copy_doc_images(_) do
    # Images can not be added to the `:extras` in `docs()`. Instead we have to copy them
    # manually to the `doc/` directory generated when running `mix hex.publish`.
    File.mkdir_p!("doc/test/images")
    File.cp!("test/images/bentheim.jpg", "doc/test/images/bentheim.jpg")
    File.mkdir_p!("doc/additional_docs")
    File.cp!("additional_docs/image_pyramid.png", "doc/additional_docs/image_pyramid.png")
  end
end
