# PublicSuffix

Parses domain names using the [Public Suffix List](https://publicsuffix.org/). Extracts the registered domain, public suffix (TLD), and host components from hostnames.

The Public Suffix List is fetched and compiled into pattern-matching function clauses at build time.

## Installation

```elixir
def deps do
  [
    {:public_suffix, "~> 0.1.0"}
  ]
end
```

## Usage

### Parse a hostname

```elixir
iex> PublicSuffix.parse("www.dept1.foo.co.uk")
{:ok, %{
  host: "www.dept1",
  domain: "foo",
  tld: "co.uk",
  tld_type: :icann,
  registered_domain: "foo.co.uk"
}}

iex> PublicSuffix.parse("username.github.io")
{:ok, %{
  host: nil,
  domain: "username",
  tld: "github.io",
  tld_type: :private,
  registered_domain: "username.github.io"
}}
```

### ICANN vs Private domains

The Public Suffix List contains both ICANN domains (like `.com`, `.co.uk`) and private domains (like `.github.io`, `.blogspot.com`). The `tld_type` field indicates which type was matched.

Use `ignore_private: true` to treat private suffixes as regular domains:

```elixir
iex> PublicSuffix.parse("username.github.io", ignore_private: true)
{:ok, %{
  host: "username",
  domain: "github",
  tld: "io",
  tld_type: :icann,
  registered_domain: "github.io"
}}
```

### Get the registered domain

```elixir
iex> PublicSuffix.registered_domain("www.dept1.foo.co.uk")
{:ok, "foo.co.uk"}

iex> PublicSuffix.registered_domain("subdomain.example.com")
{:ok, "example.com"}
```

### Get the public suffix

```elixir
iex> PublicSuffix.public_suffix("www.example.co.uk")
{:ok, "co.uk"}

iex> PublicSuffix.public_suffix("example.com")
{:ok, "com"}
```

## Implementation

The library downloads the Public Suffix List at compile time and generates approximately 10,000 pattern-matching function clauses. Hostnames are reversed before matching to enable efficient binary pattern matching.

For `"www.example.co.uk"`, the library reverses it to `"uk.co.example.www"` and matches against generated clauses:

```elixir
defp parse_impl("com." <> rest, type), do: build_result("com", rest, :exact, type)
defp parse_impl("uk.co." <> rest, type), do: build_result("co.uk", rest, :exact, type)
defp parse_impl("io.github." <> rest, type), do: build_result("github.io", rest, :exact, type)
```

The list contains three types of rules:

- Exact matches: `com`, `co.uk`, `github.io` (~9,700 rules)
- Wildcards: `*.bd`, `*.ck` (~200 rules)
- Exceptions: `!www.ck` (~8 rules)

The Public Suffix List includes approximately 6,900 ICANN domains and 3,000 private domains.

## License

MIT License

The Public Suffix List is subject to the Mozilla Public License, v. 2.0.
