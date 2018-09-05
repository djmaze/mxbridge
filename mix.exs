defmodule MxBridge.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mxbridge,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {MxBridge.Application, []},
      applications: [:romeo, :httpoison, :briefly, :confex],
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:romeo, git: "https://github.com/lmarlow/romeo.git", branch: "send_error"},
      {:httpoison, "~> 0.7"},
      {:poison, "~> 1.5"},
      {:briefly, "~> 0.3"},
      #{:distillery, "~> 2.0"}, {:fast_xml, "~> 1.1.32"},
      {:confex, "~> 3.3.1"},
    ]
  end
end
