defmodule PublicSuffix.Parser do
  @moduledoc false
  # Internal module for parsing the Public Suffix List at compile time

  @public_suffix_url "https://publicsuffix.org/list/public_suffix_list.dat"

  @doc """
  Downloads and parses the public suffix list at compile time.

  Returns a map with three categories:
  - :exact - exact suffix matches (e.g., "com" => :icann, "github.io" => :private)
  - :wildcard - wildcard entries (e.g., "*.ck" => :icann)
  - :exception - exception rules (e.g., "!www.ck" => :icann)

  Each entry maps to its type: :icann | :private
  """
  def parse_list do
    IO.puts("Downloading Public Suffix List from #{@public_suffix_url}...")
    content = download_list()
    IO.puts("Parsing Public Suffix List...")
    parse_content_with_types(content)
  end

  defp download_list do
    # Ensure inets and ssl applications are started
    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {@public_suffix_url, []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body

      {:ok, {{_, status, _}, _, _}} ->
        raise "Failed to download public suffix list: HTTP #{status}"

      {:error, reason} ->
        raise "Failed to download public suffix list: #{inspect(reason)}"
    end
  end

  defp parse_content_with_types(content) do
    # Split into ICANN and Private sections using the markers
    case String.split(content, ~r/===END ICANN DOMAINS===.*===BEGIN PRIVATE DOMAINS===/s,
           parts: 2
         ) do
      [icann_section, private_section] ->
        IO.puts("  Parsing ICANN section...")
        icann_suffixes = parse_section(icann_section, :icann)
        IO.puts("  Parsing Private section...")
        private_suffixes = parse_section(private_section, :private)

        # Merge with type information preserved
        %{
          exact: Map.merge(icann_suffixes.exact, private_suffixes.exact),
          wildcard: Map.merge(icann_suffixes.wildcard, private_suffixes.wildcard),
          exception: Map.merge(icann_suffixes.exception, private_suffixes.exception)
        }

      _ ->
        # Fallback if markers not found
        IO.puts(
          "  Warning: Could not find ICANN/Private section markers, parsing as unknown type"
        )

        parse_section(content, :unknown)
    end
  end

  defp parse_section(content, type) do
    lines = String.split(content, "\n")

    lines
    |> Enum.reduce(%{exact: %{}, wildcard: %{}, exception: %{}}, fn line, acc ->
      parse_line(line, acc, type)
    end)
  end

  defp parse_line(line, acc, type) do
    # Remove comments and whitespace
    line =
      line
      |> String.split("//")
      |> List.first()
      |> String.trim()

    cond do
      # Skip empty lines
      line == "" ->
        acc

      # Exception rule (starts with !)
      String.starts_with?(line, "!") ->
        suffix = String.trim_leading(line, "!")
        %{acc | exception: Map.put(acc.exception, suffix, type)}

      # Wildcard rule (starts with *.)
      String.starts_with?(line, "*.") ->
        %{acc | wildcard: Map.put(acc.wildcard, line, type)}

      # Exact match
      true ->
        %{acc | exact: Map.put(acc.exact, line, type)}
    end
  end
end
