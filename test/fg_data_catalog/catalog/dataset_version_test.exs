defmodule FGDataCatalog.Catalog.DatasetVersionTest do
  use ExUnit.Case, async: true

  alias FGDataCatalog.Catalog.DatasetVersion

  # NOTE(Claude-Opus-5.5 2026-11-26): the date inputs' min and max.
  test "release dates are offered from 2016 to the end of next year" do
    assert DatasetVersion.release_date_bounds(~D[2026-11-26]) == {"2016-01-01", "2027-12-31"}
  end
end
