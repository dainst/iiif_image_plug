defmodule IIIFImagePlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :iiif_image_plug,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [mod: {IIIFImagePlug.Application, []}, extra_applications: [:logger]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.16"},
      {:vix, "~> 0.33.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6", only: [:test, :dev]}
    ]
  end
end
