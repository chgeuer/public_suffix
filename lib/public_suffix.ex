defmodule PublicSuffix do
  @moduledoc """
  A library for parsing domain names and extracting their components based on the Public Suffix List.

  This library parses hostnames to extract:
  - The public suffix (TLD) - e.g., "co.uk", "com"
  - The registered domain - e.g., "example.com"
  - The host part - e.g., "www.dept1"

  The Public Suffix List is downloaded at compile time from https://publicsuffix.org/list/public_suffix_list.dat
  and compiled into pattern-matching function clauses for maximum performance.

  ## Performance

  This library uses Elixir's macro system to generate ~10,000 individual pattern-matching function
  clauses at compile time. Hostnames are reversed (e.g., "uk.co.example.www") and matched using
  string pattern matching for optimal BEAM performance:

  - Zero runtime overhead for loading or parsing the suffix list
  - No runtime map lookups - pure Erlang string pattern matching
  - Reversed hostname matching (e.g., `"uk.co." <> rest`) allows BEAM to match from TLD first
  - The BEAM VM's optimized binary pattern matching provides maximum performance
  - All 9,700+ suffixes, 200+ wildcards, and exception rules are compiled into your application

  ## Examples

      iex> PublicSuffix.parse("www.dept1.foo.co.uk")
      {:ok, %{host: "www.dept1", domain: "foo", tld: "co.uk", tld_type: :icann, registered_domain: "foo.co.uk"}}

      iex> PublicSuffix.parse("example.com")
      {:ok, %{host: nil, domain: "example", tld: "com", tld_type: :icann, registered_domain: "example.com"}}
  """

  # Parse the list at compile time
  suffixes = PublicSuffix.Parser.parse_list()

  # Build a MapSet of all TLDs (reversed) for the final catch-all clause
  all_tlds =
    (Map.keys(suffixes.exact) ++ Map.keys(suffixes.wildcard) ++ Map.keys(suffixes.exception))
    |> Enum.map(fn suffix -> suffix |> String.split(".") |> Enum.reverse() |> Enum.join(".") end)
    |> MapSet.new()

  @tlds all_tlds

  # Deduplicate wildcard bases to avoid generating duplicate clauses
  # Multiple wildcards like *.fk, *.np, *.pg all have the same base "*" when reversed
  wildcard_bases =
    suffixes.wildcard
    |> Map.keys()
    |> Enum.map(fn suffix ->
      # For "*.ck", parts = ["*", "ck"]
      # We want the base TLD without the wildcard
      # Remove the leading "*." to get the base, then reverse it
      tld = String.replace_prefix(suffix, "*.", "")
      tld_reversed = tld |> String.split(".") |> Enum.reverse() |> Enum.join(".")
      {tld_reversed, tld}
    end)
    |> Enum.uniq_by(fn {tld_reversed, _} -> tld_reversed end)

  @doc """
  Parses a hostname and returns its components.

  Returns `{:ok, map}` with the following keys:
  - `:host` - The subdomain part (nil if just the registered domain)
  - `:domain` - The domain name part
  - `:tld` - The public suffix (top-level domain)
  - `:tld_type` - The type of TLD (`:icann` or `:private`)
  - `:registered_domain` - The domain + TLD

  Returns `{:error, reason}` if the hostname is invalid or cannot be parsed.

  ## Options

  - `:ignore_private` - When `true`, treats private domains (like `github.io`) as part
    of the domain instead of the TLD. Defaults to `false`.

  ## Examples

      iex> PublicSuffix.parse("www.dept1.foo.co.uk")
      {:ok, %{host: "www.dept1", domain: "foo", tld: "co.uk", tld_type: :icann, registered_domain: "foo.co.uk"}}

      iex> PublicSuffix.parse("example.com")
      {:ok, %{host: nil, domain: "example", tld: "com", tld_type: :icann, registered_domain: "example.com"}}

      iex> PublicSuffix.parse("username.github.io")
      {:ok, %{host: nil, domain: "username", tld: "github.io", tld_type: :private, registered_domain: "username.github.io"}}

      iex> PublicSuffix.parse("username.github.io", ignore_private: true)
      {:ok, %{host: "username", domain: "github", tld: "io", tld_type: :icann, registered_domain: "github.io"}}
  """
  def parse(hostname, opts \\ [])

  def parse(hostname, opts) when is_binary(hostname) do
    ignore_private = Keyword.get(opts, :ignore_private, false)

    reversed = hostname |> String.downcase() |> reverse_hostname()

    case parse_impl(reversed) do
      {:ok, %{tld_type: :private} = result} when ignore_private ->
        # Re-parse without the private TLD - treat it as part of the domain
        reparse_ignoring_private(hostname |> String.downcase(), result.tld)

      result ->
        result
    end
  end

  def parse(_, _), do: {:error, :invalid_input}

  # Helper to re-parse when ignoring a private TLD
  # For "username.github.io" with private_tld="github.io", we want:
  #   domain="github", host="username", tld="io" (the parent ICANN TLD)
  defp reparse_ignoring_private(hostname, private_tld) do
    # Get the parent TLD by taking the last part of the private TLD
    # "github.io" -> "io"
    parent_tld = private_tld |> String.split(".") |> List.last()

    # Now construct what we want: everything before the private TLD + the parent TLD
    # "username.github.io" with private="github.io", parent="io"
    # Remove ".github.io" and add ".io"
    # But actually need to keep "github" as part of the domain
    #
    # Split approach: ["username", "github", "io"]
    # We want: domain="github", host="username", tld="io"
    # So take all parts except the last one (which is "io")
    # Then split that into domain (last) and host (rest)

    parts = String.split(hostname, ".")
    # For ["username", "github", "io"], take all but last = ["username", "github"]
    domain_and_host = Enum.drop(parts, -(String.split(parent_tld, ".") |> length()))

    case domain_and_host do
      [] ->
        # No domain part left
        {:error, :is_public_suffix}

      [domain] ->
        # Just domain, no host
        {:ok,
         %{
           host: nil,
           domain: domain,
           tld: parent_tld,
           tld_type: :icann,
           registered_domain: domain <> "." <> parent_tld
         }}

      parts ->
        # Have both domain and host
        domain = List.last(parts)
        host_parts = Enum.drop(parts, -1)
        host = Enum.join(host_parts, ".")

        {:ok,
         %{
           host: host,
           domain: domain,
           tld: parent_tld,
           tld_type: :icann,
           registered_domain: domain <> "." <> parent_tld
         }}
    end
  end

  split_reverse_join = &(&1 |> String.split(".") |> Enum.reverse() |> Enum.join("."))

  # Generate function clauses for exception matches (highest priority)
  # Exception rules start with ! and indicate the suffix is NOT a public suffix
  # Example: !www.ck means www.ck is registerable (exception to *.ck wildcard)
  # The parent of the exception becomes the public suffix
  for {suffix, type} <- suffixes.exception do
    # For "www.ck", the public suffix is "ck", and "www" is the domain
    # ["www", "ck"]
    parts = String.split(suffix, ".")
    # "www"
    domain_part = List.first(parts)
    # ["ck"]
    tld_parts = List.delete_at(parts, 0)
    # "ck"
    tld = Enum.join(tld_parts, ".")
    # "ck.www"
    reversed = split_reverse_join.(suffix)

    # Match the exception with more parts (e.g., "ck.www.subdomain")
    defp parse_impl(unquote(reversed) <> "." <> rest),
      do:
        build_result(unquote(tld), unquote(domain_part) <> "." <> rest, :exception, unquote(type))

    # Match exactly the exception (e.g., "ck.www") - domain is the exception label
    defp parse_impl(unquote(reversed)) do
      {:ok,
       %{
         host: nil,
         domain: unquote(domain_part),
         tld: unquote(tld),
         tld_type: unquote(type),
         registered_domain: unquote(suffix)
       }}
    end
  end

  # Check if input is a bare public suffix (literal TLD)
  # This must come before exact matches to prevent partial matches on multi-level TLDs
  defp parse_impl(reversed_hostname) when is_binary(reversed_hostname) do
    if MapSet.member?(@tlds, reversed_hostname) do
      {:error, :is_public_suffix}
    else
      parse_impl_clauses(reversed_hostname)
    end
  end

  # Generate function clauses for exact matches
  # These are explicit public suffixes like "com", "co.uk", "github.io"
  # Sort by number of dots descending so more specific matches come first (e.g., "co.uk" before "uk")
  # We only generate the clause for matching with a domain part
  # Bare TLDs are handled by the @tlds check above
  for {suffix, type} <-
        Enum.sort_by(suffixes.exact, fn {s, _} -> -length(String.split(s, ".")) end) do
    reversed = split_reverse_join.(suffix)

    defp parse_impl_clauses(unquote(reversed) <> "." <> rest),
      do: build_result(unquote(suffix), rest, :exact, unquote(type))
  end

  # Generate function clauses for wildcard matches
  # Wildcards like *.ck mean all second-level domains under .ck are public suffixes
  # We deduplicate by base to avoid generating duplicate clauses
  for {tld_reversed, tld} <- wildcard_bases do
    # Get the type for this wildcard base
    wildcard_suffix = "*." <> tld
    type = Map.get(suffixes.wildcard, wildcard_suffix, :unknown)

    # Match pattern like "ck." <> wildcard_part where wildcard_part contains at least one dot
    defp parse_impl_clauses(unquote(tld_reversed) <> "." <> rest) do
      case String.split(rest, ".", parts: 2) do
        [wildcard_label, domain_rest] ->
          # The wildcard label plus the TLD form the public suffix
          full_suffix = wildcard_label <> "." <> unquote(tld)
          build_result(full_suffix, domain_rest, :wildcard, unquote(type))

        [_single_label] ->
          # Just the wildcard part, no domain - this is a public suffix
          {:error, :is_public_suffix}
      end
    end
  end

  # Final catch-all for invalid hostnames
  defp parse_impl_clauses(_reversed_hostname), do: {:error, :invalid_hostname}

  # Build the result from the matched suffix and remaining parts
  defp build_result(tld, rest, _match_type, tld_type) do
    case String.split(rest, ".", parts: 2) do
      [domain, host_reversed] ->
        # We have both domain and host parts
        host = reverse_hostname(host_reversed)

        {:ok,
         %{
           host: host,
           domain: domain,
           tld: tld,
           tld_type: tld_type,
           registered_domain: domain <> "." <> tld
         }}

      [domain] ->
        # Just the domain, no host
        {:ok,
         %{
           host: nil,
           domain: domain,
           tld: tld,
           tld_type: tld_type,
           registered_domain: domain <> "." <> tld
         }}

      [] ->
        # No domain part - this is just the public suffix
        {:error, :is_public_suffix}
    end
  end

  @doc """
  Returns the registered domain for a hostname.

  ## Examples

      iex> PublicSuffix.registered_domain("www.dept1.foo.co.uk")
      {:ok, "foo.co.uk"}

      iex> PublicSuffix.registered_domain("example.com")
      {:ok, "example.com"}
  """
  def registered_domain(hostname) do
    case parse(hostname) do
      {:ok, result} -> {:ok, result.registered_domain}
      error -> error
    end
  end

  @doc """
  Returns the public suffix (TLD) for a hostname.

  ## Examples

      iex> PublicSuffix.public_suffix("www.dept1.foo.co.uk")
      {:ok, "co.uk"}

      iex> PublicSuffix.public_suffix("example.com")
      {:ok, "com"}
  """
  def public_suffix(hostname) do
    case parse(hostname) do
      {:ok, result} -> {:ok, result.tld}
      error -> error
    end
  end

  # Reverse the hostname labels
  # "www.example.com" -> "com.example.www"
  defp reverse_hostname(hostname) do
    hostname
    |> String.split(".")
    |> Enum.reverse()
    |> Enum.join(".")
  end
end
