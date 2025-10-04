defmodule PublicSuffixTest do
  use ExUnit.Case
  doctest PublicSuffix

  describe "parse/1" do
    test "parses simple .com domain" do
      assert {:ok,
              %{
                domain: "example",
                tld: "com",
                tld_type: :icann,
                registered_domain: "example.com",
                host: nil
              }} ==
               PublicSuffix.parse("example.com")
    end

    test "parse Azure blob" do
      assert {:ok,
              %{
                host: nil,
                domain: "chgeuer",
                tld: "blob.core.windows.net",
                tld_type: :private,
                registered_domain: "chgeuer.blob.core.windows.net"
              }} == PublicSuffix.parse("chgeuer.blob.core.windows.net")
    end

    test "parses domain with subdomain" do
      assert {:ok,
              %{
                domain: "example",
                tld: "com",
                tld_type: :icann,
                registered_domain: "example.com",
                host: "www"
              }} ==
               PublicSuffix.parse("www.example.com")
    end

    test "parses domain with multiple subdomains" do
      assert {:ok,
              %{
                domain: "foo",
                tld: "co.uk",
                tld_type: :icann,
                registered_domain: "foo.co.uk",
                host: "www.dept1"
              }} ==
               PublicSuffix.parse("www.dept1.foo.co.uk")
    end

    test "parses multi-level TLD" do
      assert {:ok,
              %{
                domain: "example",
                tld: "co.uk",
                tld_type: :icann,
                registered_domain: "example.co.uk",
                host: nil
              }} ==
               PublicSuffix.parse("example.co.uk")
    end

    test "handles case insensitivity" do
      assert {:ok,
              %{
                domain: "example",
                tld: "com",
                tld_type: :icann,
                registered_domain: "example.com",
                host: "www"
              }} ==
               PublicSuffix.parse("WWW.EXAMPLE.COM")
    end

    test "handles just a public suffix" do
      assert {:error, :is_public_suffix} == PublicSuffix.parse("com")
    end

    test "handles just a multi-level public suffix" do
      assert {:error, :is_public_suffix} == PublicSuffix.parse("co.uk")
    end

    test "handles invalid input types" do
      assert {:error, :invalid_input} == PublicSuffix.parse(123)
      assert {:error, :invalid_input} == PublicSuffix.parse(nil)
    end

    test "parses GitHub Pages domains" do
      assert {:ok,
              %{
                domain: "username",
                tld: "github.io",
                tld_type: :private,
                registered_domain: "username.github.io",
                host: nil
              }} == PublicSuffix.parse("username.github.io")
    end

    test "parses domains with deep subdomains" do
      assert {:ok,
              %{
                domain: "example",
                tld: "com",
                tld_type: :icann,
                host: "a.b.c.d",
                registered_domain: "example.com"
              }} ==
               PublicSuffix.parse("a.b.c.d.example.com")
    end

    test "handles Japanese domains" do
      assert {:ok,
              %{
                domain: "example",
                tld: "jp",
                tld_type: :icann,
                registered_domain: "example.jp",
                host: nil
              }} ==
               PublicSuffix.parse("example.jp")
    end

    test "handles .org domains" do
      assert {:ok,
              %{
                domain: "example",
                tld: "org",
                tld_type: :icann,
                registered_domain: "example.org",
                host: "subdomain"
              }} ==
               PublicSuffix.parse("subdomain.example.org")
    end

    test "ignore_private option with private domain" do
      assert {:ok,
              %{
                domain: "github",
                tld: "io",
                tld_type: :icann,
                registered_domain: "github.io",
                host: "username"
              }} ==
               PublicSuffix.parse("username.github.io", ignore_private: true)
    end

    test "ignore_private option with ICANN domain" do
      assert {:ok,
              %{
                domain: "example",
                tld: "com",
                tld_type: :icann,
                registered_domain: "example.com",
                host: "www"
              }} ==
               PublicSuffix.parse("www.example.com", ignore_private: true)
    end
  end

  describe "registered_domain/1" do
    test "returns registered domain for simple domain" do
      assert {:ok, "example.com"} == PublicSuffix.registered_domain("www.example.com")
    end

    test "returns registered domain for multi-level TLD" do
      assert {:ok, "foo.co.uk"} == PublicSuffix.registered_domain("www.dept1.foo.co.uk")
    end

    test "returns error for public suffix" do
      assert {:error, :is_public_suffix} == PublicSuffix.registered_domain("com")
    end
  end

  describe "public_suffix/1" do
    test "returns public suffix for simple TLD" do
      assert {:ok, "com"} == PublicSuffix.public_suffix("www.example.com")
    end

    test "returns public suffix for multi-level TLD" do
      assert {:ok, "co.uk"} == PublicSuffix.public_suffix("www.dept1.foo.co.uk")
    end

    test "returns public suffix for GitHub Pages" do
      assert {:ok, "github.io"} == PublicSuffix.public_suffix("username.github.io")
    end
  end
end
