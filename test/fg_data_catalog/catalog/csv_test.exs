defmodule FGDataCatalog.Catalog.CSVTest do
  use ExUnit.Case, async: true

  alias FGDataCatalog.Catalog.CSV

  doctest CSV, import: true

  describe "parse/1" do
    test "splits rows and fields, tagging each row with its first line" do
      assert CSV.parse("a,b\nc,d") == {:ok, [{1, ["a", "b"]}, {2, ["c", "d"]}]}
    end

    test "accepts \\r\\n and \\r line endings and a trailing newline" do
      assert CSV.parse("a,b\r\nc,d\re\n") ==
               {:ok, [{1, ["a", "b"]}, {2, ["c", "d"]}, {3, ["e"]}]}
    end

    test "skips blank lines but keeps empty fields" do
      assert CSV.parse("\na,\n  \n,b\n") == {:ok, [{2, ["a", ""]}, {4, ["", "b"]}]}
    end

    test "reads quoted fields with commas, doubled quotes and newlines" do
      assert CSV.parse(~s(x,"a, ""b""\nc"\ny,z)) ==
               {:ok, [{1, ["x", ~s(a, "b"\nc)]}, {3, ["y", "z"]}]}
    end

    test "allows spaces after a closing quote" do
      assert CSV.parse(~s("a"  ,b)) == {:ok, [{1, ["a", "b"]}]}
    end

    test "reports an unclosed quote at the line where its row starts" do
      assert CSV.parse(~s(a\nb,"c\nd)) == {:error, 2, "a quoted value is not closed"}
    end

    test "reports text after a closing quote" do
      assert CSV.parse(~s(a\n"b"c)) == {:error, 2, "unexpected text after a closing quote"}
    end

    # NOTE(Claude 2026-11-06): cells copied from a spreadsheet.
    test "reads text with a tab as tab-separated, commas being part of values" do
      assert CSV.parse("2013\t1,200\r\nAGE\t\"Age\tin years\"\n") ==
               {:ok, [{1, ["2013", "1,200"]}, {2, ["AGE", "Age\tin years"]}]}
    end

    test "empty text has no rows" do
      assert CSV.parse("") == {:ok, []}
    end
  end

  describe "dump/1" do
    test "quotes only the values that need it, and round-trips through parse/1" do
      rows = [["plain", ~s(with "quotes")], ["a, b", " padded"], ["multi\nline", nil], [2025, 7]]
      text = CSV.dump(rows)

      assert text ==
               ~s(plain,"with ""quotes"""\n"a, b"," padded"\n"multi\nline",\n2025,7)

      assert {:ok, parsed} = CSV.parse(text)

      assert Enum.map(parsed, &elem(&1, 1)) ==
               [
                 ["plain", ~s(with "quotes")],
                 ["a, b", " padded"],
                 ["multi\nline", ""],
                 ["2025", "7"]
               ]
    end
  end
end
