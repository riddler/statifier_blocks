defmodule StatifierBlocks.PackageFilesTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Hex.Build

  # The files the package tarball carries, as Hex itself lists them: the
  # same package preparation `mix hex.build` and `mix hex.publish` run,
  # read in-process and offline (it builds nothing and asks no server).
  # Hex is loaded by every mix run that resolves hex dependencies, but a
  # mix run prunes the archive's directory from the code path, so the
  # directory Hex was loaded from is added back before its build task
  # module is asked.
  defp package_files do
    case :code.which(Hex) do
      path when is_list(path) ->
        path |> Path.dirname() |> Code.append_path()

      other ->
        flunk(
          "the Hex archive is not loaded (#{inspect(other)}), so its file list cannot be read"
        )
    end

    Build.prepare_package().meta.files
  end

  # Sabotage: priv/schemas dropped from the package files: list -> the membership check goes red.
  test "the built package carries the block document schema" do
    assert "priv/schemas/block-document.schema.json" in package_files()
  end
end
