defmodule FGDataCatalog.Catalog.CSV do
  @moduledoc """
  A small CSV reader and writer (RFC 4180, comma-separated), for the lists that
  are entered as pasted text: a version's data dictionary and yearly counts.

  NOTE(Claude 2026-11-06): text that contains a tab is read as tab-separated
  instead, as cells copied from a spreadsheet are pasted that way. Commas are
  then part of the values.

  Fields may be quoted (`"a, b"`), with `""` for a quote inside a quoted field.
  Lines may end in `\\n`, `\\r\\n` or `\\r`. Blank lines are skipped.
  """

  @doc """
  Parses `text` into rows of fields, each row tagged with the line it starts on.

      iex> parse(~s(a,"b, c"\\n\\nd))
      {:ok, [{1, ["a", "b, c"]}, {3, ["d"]}]}

  Returns `{:error, line, message}` if `text` is not valid CSV.
  """
  def parse(text) when is_binary(text) do
    delimiter = if String.contains?(text, "\t"), do: ?\t, else: ?,

    field(delimiter, String.replace(text, ["\r\n", "\r"], "\n"), 1, 1, [], [])
  end

  # NOTE(Claude 2026-11-06): `d` is the delimiter (comma or tab), `line` the
  # current line, `start` the line the current row started on (a quoted field
  # may span lines), `fields` the current row's fields and `rows` the finished
  # rows, both reversed.
  defp field(d, <<?", rest::binary>>, line, start, fields, rows),
    do: quoted(d, rest, line, start, fields, rows, [])

  defp field(d, text, line, start, fields, rows),
    do: unquoted(d, text, line, start, fields, rows, [])

  defp unquoted(d, <<d, rest::binary>>, line, start, fields, rows, acc),
    do: field(d, rest, line, start, [value(acc) | fields], rows)

  defp unquoted(d, <<?\n, rest::binary>>, line, start, fields, rows, acc),
    do: field(d, rest, line + 1, line + 1, [], add_row(rows, start, [value(acc) | fields]))

  defp unquoted(_d, <<>>, _line, start, fields, rows, acc),
    do: done(rows, start, [value(acc) | fields])

  defp unquoted(d, <<c, rest::binary>>, line, start, fields, rows, acc),
    do: unquoted(d, rest, line, start, fields, rows, [acc, c])

  defp quoted(d, <<?", ?", rest::binary>>, line, start, fields, rows, acc),
    do: quoted(d, rest, line, start, fields, rows, [acc, ?"])

  defp quoted(d, <<?", rest::binary>>, line, start, fields, rows, acc),
    do: after_quoted(d, rest, line, start, [value(acc) | fields], rows)

  defp quoted(d, <<?\n, rest::binary>>, line, start, fields, rows, acc),
    do: quoted(d, rest, line + 1, start, fields, rows, [acc, ?\n])

  defp quoted(d, <<c, rest::binary>>, line, start, fields, rows, acc),
    do: quoted(d, rest, line, start, fields, rows, [acc, c])

  defp quoted(_d, <<>>, _line, start, _fields, _rows, _acc),
    do: {:error, start, "a quoted value is not closed"}

  defp after_quoted(d, <<d, rest::binary>>, line, start, fields, rows),
    do: field(d, rest, line, start, fields, rows)

  defp after_quoted(d, <<?\n, rest::binary>>, line, start, fields, rows),
    do: field(d, rest, line + 1, line + 1, [], add_row(rows, start, fields))

  defp after_quoted(_d, <<>>, _line, start, fields, rows), do: done(rows, start, fields)

  defp after_quoted(d, <<c, rest::binary>>, line, start, fields, rows)
       when c in [?\s, ?\t] and c != d,
       do: after_quoted(d, rest, line, start, fields, rows)

  defp after_quoted(_d, _text, line, _start, _fields, _rows),
    do: {:error, line, "unexpected text after a closing quote"}

  defp value(acc), do: IO.iodata_to_binary(acc)

  defp done(rows, start, fields), do: {:ok, rows |> add_row(start, fields) |> Enum.reverse()}

  # NOTE(Claude 2026-11-03): a row with a single empty field is a blank line.
  defp add_row(rows, start, fields) do
    case Enum.reverse(fields) do
      [field] = row -> if String.trim(field) == "", do: rows, else: [{start, row} | rows]
      row -> [{start, row} | rows]
    end
  end

  @doc """
  Writes `rows` (lists of strings, integers or `nil`) as CSV, one row per line.
  Values are quoted only when needed.

      iex> dump([["a", "b, c"], [2025, nil]])
      ~s(a,"b, c"\\n2025,)
  """
  def dump(rows) do
    Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, ",", &dump_value/1) end)
  end

  defp dump_value(nil), do: ""

  defp dump_value(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]) or String.trim(value) != value do
      ~s(") <> String.replace(value, ~s("), ~s("")) <> ~s(")
    else
      value
    end
  end
end
