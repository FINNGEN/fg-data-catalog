defmodule FGDataCatalogWeb.TagLinesTest do
  # NOTE(Claude Opus 5.5 2026-11-17): a catalog row's tags, split in two lines
  # of about the same width.
  use ExUnit.Case, async: true

  import FGDataCatalogWeb.CatalogComponents, only: [tag_lines: 1]

  test "no tags, no line; a single tag, one line" do
    assert tag_lines([]) == []
    assert tag_lines(["Phenotype"]) == [["Phenotype"]]
  end

  test "two tags, one on each line" do
    assert tag_lines(["Registry", "Medication"]) == [["Medication"], ["Registry"]]
  end

  test "balances the widths of the lines, in sorted order" do
    assert tag_lines(["Phenotype", "Longitudinal", "Measurements"]) ==
             [["Longitudinal"], ["Measurements", "Phenotype"]]

    assert tag_lines(["a", "b", "c", "d"]) == [["a", "b"], ["c", "d"]]
    assert tag_lines(["a", "b", "c"]) == [["a", "b"], ["c"]]
    assert tag_lines(["Longitudinal", "a", "b"]) == [["a", "b"], ["Longitudinal"]]
  end
end
