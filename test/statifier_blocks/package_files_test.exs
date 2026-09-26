defmodule StatifierBlocks.PackageFilesTest do
  use ExUnit.Case, async: true

  # The package's `files:` list expanded the way Hex expands it: an entry
  # naming a directory means every file beneath it.
  defp package_files do
    Mix.Project.config()
    |> Keyword.fetch!(:package)
    |> Keyword.fetch!(:files)
    |> Enum.flat_map(fn entry ->
      if File.dir?(entry) do
        entry |> Path.join("**") |> Path.wildcard() |> Enum.reject(&File.dir?/1)
      else
        [entry]
      end
    end)
  end

  # Sabotage: priv/schemas dropped from the package files: list -> the membership check goes red.
  test "the built package carries the block document schema" do
    assert "priv/schemas/block-document.schema.json" in package_files()
  end
end
